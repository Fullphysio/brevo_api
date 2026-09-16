import 'model.dart';
import 'naming.dart';
import 'spec.dart';

/// Classifies every reachable shape of the vendored Brevo specification into
/// the closed IR the emitters consume.
///
/// Rules specific to this specification, all deliberate:
///
/// - Inline schemas are named after their position: a request body after the
///   upstream request type, a response after the upstream response type, a
///   nested object `<Owner><Property>` and an array item
///   `<Owner><Property>Item`, exactly as `@getbrevo/brevo` nests them.
/// - `allOf` is flattened; a part that is a lone `$ref` without additions
///   resolves to the referenced class.
/// - `oneOf` / `anyOf` carry no discriminator anywhere in the spec. Object
///   alternatives are merged into one class whose fields are the union of
///   every alternative's (required only if every alternative requires it);
///   anything else decodes as `Object?`.
/// - An object without properties, whatever its `additionalProperties`, is a
///   `Map<String, Object?>`.
/// - Response classes are tolerant (every field nullable, lists and maps
///   default to empty); request classes honour `required`.
/// - Every 2xx response with content contributes to the response class, so
///   `POST /smtp/email` exposes the `batchId` of its 202 as well as the
///   `messageId` of its 201.
final class Resolver {
  Resolver(this.spec, this.resources, this.mappings, this.specDigest);

  final OpenApiSpec spec;
  final ResourceMap resources;
  final WireMockMappings mappings;
  final String specDigest;

  final Map<String, ClassIr> _classes = {};
  final Map<String, EnumIr> _enums = {};
  final Map<String, String> _classStructures = {};
  final Map<String, String> _enumStructures = {};
  final Map<String, NamespaceIr> _namespaces = {};
  final Set<String> _requestComponents = {};
  final Set<String> _multipartComponents = {};
  final Map<String, String> _componentGroups = {};
  final List<MockCaseIr> _mockCases = [];

  GeneratorIr resolve() {
    final keys = spec.operationKeys();
    for (final key in keys) {
      if (!resources.operations.containsKey(key)) {
        throw StateError('$key is not in tool/spec/resources.yaml');
      }
    }
    for (final key in resources.operations.keys) {
      if (!keys.contains(key)) {
        throw StateError('resources.yaml maps $key, which the spec lacks');
      }
    }
    _collectRequestComponents(keys);
    _collectComponentGroups(keys);
    for (final name in spec.schemas.keys.toList()..sort()) {
      final schema = spec.schema(name);
      if (_isObjectLike(schema) && _hasProperties(schema)) {
        _componentClass(name);
      }
    }
    for (final key in keys) {
      _resolveOperation(key);
    }
    _resolveMockCases();
    return GeneratorIr(
      classes: Map.fromEntries(
          _classes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      enums: Map.fromEntries(
          _enums.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      namespaces: Map.fromEntries(
          _namespaces.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      mockCases: _mockCases,
      specDigest: specDigest,
    );
  }

  void _collectRequestComponents(List<String> keys) {
    for (final key in keys) {
      final body = spec.operation(key)['requestBody'] as JsonMap?;
      if (body == null) continue;
      final content = body['content'] as JsonMap;
      for (final entry in content.entries) {
        final schema = (entry.value as JsonMap)['schema'] as JsonMap?;
        if (schema == null) continue;
        final name = spec.refName(schema);
        if (name != null) {
          _requestComponents.add(name);
          if (entry.key.startsWith('multipart/')) {
            _multipartComponents.add(name);
          }
        }
      }
    }
  }

  void _collectComponentGroups(List<String> keys) {
    final usage = <String, Set<String>>{};
    void note(JsonMap? node, String namespace) {
      if (node == null) return;
      final name = spec.refName(node);
      if (name != null) {
        (usage[name] ??= {}).add(namespace);
        return;
      }
      for (final value in node.values) {
        if (value is JsonMap) note(value, namespace);
        if (value is List) {
          for (final item in value) {
            if (item is JsonMap) note(item, namespace);
          }
        }
      }
    }

    for (final key in keys) {
      final namespace = resources.operations[key]!.namespace;
      final op = spec.operation(key);
      note(op['requestBody'] as JsonMap?, namespace);
      note(op['responses'] as JsonMap?, namespace);
    }
    for (var changed = true; changed;) {
      changed = false;
      for (final entry in usage.entries.toList()) {
        final referenced = <String>{};
        note(spec.schema(entry.key), '');
        void collect(JsonMap node) {
          final name = spec.refName(node);
          if (name != null) {
            referenced.add(name);
            return;
          }
          for (final value in node.values) {
            if (value is JsonMap) collect(value);
            if (value is List) {
              for (final item in value) {
                if (item is JsonMap) collect(item);
              }
            }
          }
        }

        collect(spec.schema(entry.key));
        for (final name in referenced) {
          final target = usage[name] ??= {};
          final before = target.length;
          target.addAll(entry.value.where((n) => n.isNotEmpty));
          if (target.length != before) changed = true;
        }
      }
    }
    for (final entry in usage.entries) {
      final namespaces = entry.value.where((n) => n.isNotEmpty).toSet();
      _componentGroups[entry.key] =
          namespaces.length == 1 ? namespaces.single : 'shared';
    }
  }

  String _group(String component) => _componentGroups[component] ?? 'shared';

  String _componentClass(String name) {
    final className = pascalCase(name);
    if (_classes.containsKey(className)) return className;
    final node = spec.deref(spec.schema(name));
    final kind =
        _requestComponents.contains(name) ? ClassKind.request : ClassKind.model;
    final multipart = _multipartComponents.contains(name);
    return _classFrom(
      _mergeShape(node, kind: kind),
      className,
      kind: kind,
      group: _group(name),
      origin: 'components/schemas/$name',
      multipart: multipart,
    );
  }

  /// Produces a plain object node (`properties` + `required`) from any
  /// object-like node: `allOf` flattened, `oneOf` / `anyOf` of objects merged,
  /// and the node's own `properties` / `required` layered on top.
  JsonMap _mergeShape(JsonMap node, {required ClassKind kind}) {
    final resolved = spec.deref(node);
    JsonMap? combined;
    if (resolved.containsKey('allOf')) {
      combined = _mergeAll(
        [
          for (final part in (resolved['allOf'] as List).cast<JsonMap>())
            _mergeShape(part, kind: kind)
        ],
        requireAll: true,
      );
    } else {
      for (final key in const ['oneOf', 'anyOf']) {
        if (resolved.containsKey(key)) {
          combined = _mergeAll(
            [
              for (final alternative in (resolved[key] as List).cast<JsonMap>())
                _mergeShape(alternative, kind: kind)
            ],
            requireAll: false,
          );
        }
      }
    }
    if (combined == null) return resolved;
    final own = <String, Object?>{
      'type': 'object',
      if (resolved.containsKey('properties'))
        'properties': resolved['properties'],
      if (resolved.containsKey('required')) 'required': resolved['required'],
    };
    return {
      ..._mergeAll([combined, own], requireAll: true),
      if (resolved['description'] != null)
        'description': resolved['description'],
    };
  }

  JsonMap _mergeAll(List<JsonMap> parts, {required bool requireAll}) {
    final properties = <String, Object?>{};
    Set<String>? required;
    var anyProperties = false;
    for (final part in parts) {
      final partProperties = part['properties'] as JsonMap?;
      if (partProperties != null) {
        anyProperties = true;
        properties.addAll(partProperties);
      }
      final partRequired =
          ((part['required'] as List?) ?? const []).cast<String>().toSet();
      if (requireAll) {
        (required ??= {}).addAll(partRequired);
      } else {
        required = required == null
            ? partRequired
            : required.intersection(partRequired);
      }
    }
    return {
      'type': 'object',
      if (anyProperties) 'properties': properties,
      if (required != null && required.isNotEmpty)
        'required': (required.toList()..sort()),
    };
  }

  bool _isObjectLike(JsonMap node) {
    final resolved = spec.deref(node);
    if (resolved.containsKey('properties') ||
        resolved.containsKey('allOf') ||
        resolved['type'] == 'object') {
      return true;
    }
    for (final key in const ['oneOf', 'anyOf']) {
      final alternatives = resolved[key];
      if (alternatives is List) {
        return alternatives.cast<JsonMap>().every(_isObjectLike);
      }
    }
    return false;
  }

  bool _isFreeFormMap(JsonMap node) {
    final properties = node['properties'];
    if (properties is JsonMap && properties.isEmpty) return true;
    final description = node['description'];
    return description is String &&
        description.toLowerCase().contains('key-value');
  }

  bool _hasProperties(JsonMap node) {
    final resolved = spec.deref(node);
    if (_isFreeFormMap(resolved)) return false;
    if (resolved.containsKey('properties')) return true;
    for (final key in const ['allOf', 'oneOf', 'anyOf']) {
      final parts = resolved[key];
      if (parts is List && parts.cast<JsonMap>().any(_hasProperties)) {
        return true;
      }
    }
    return false;
  }

  String _classFrom(
    JsonMap node,
    String className, {
    required ClassKind kind,
    required String group,
    String? origin,
    bool multipart = false,
  }) {
    final structure = _structure(node);
    final existing = _classes[className];
    if (existing != null) {
      if (_classStructures[className] == structure) return className;
      return _classFrom(node, '${className}Alt',
          kind: kind, group: group, origin: origin, multipart: multipart);
    }
    _classStructures[className] = structure;
    final fields = <FieldIr>[];
    _classes[className] = ClassIr(
      className: className,
      kind: kind,
      group: group,
      fields: fields,
      docs: _docOf(node),
      origin: origin,
      multipart: multipart,
    );
    final properties = (node['properties'] as JsonMap?) ?? const {};
    final required =
        ((node['required'] as List?) ?? const []).cast<String>().toSet();
    final usedNames = <String>{};
    for (final entry in properties.entries) {
      final property = entry.value as JsonMap;
      var dartName = fieldName(entry.key);
      while (!usedNames.add(dartName)) {
        dartName = '${dartName}_';
      }
      final type = _typeOf(property,
          owner: className, prop: entry.key, kind: kind, group: group);
      final format = spec.deref(property)['format'];
      fields.add(FieldIr(
        wireName: entry.key,
        dartName: dartName,
        type: type,
        required: kind == ClassKind.request && required.contains(entry.key),
        docs: _docOf(property),
        deprecated: property['deprecated'] == true,
        hasDateGetter: type is IrString &&
            (format == 'date-time' ||
                format == 'date' ||
                RegExp(r'(At|Date)$').hasMatch(entry.key)),
      ));
    }
    return className;
  }

  IrType _typeOf(
    JsonMap node, {
    required String owner,
    required String prop,
    required ClassKind kind,
    required String group,
  }) {
    final refName = spec.refName(node);
    if (refName != null) {
      final target = spec.schema(refName);
      if (_isObjectLike(target) && _hasProperties(target)) {
        return IrRef(_componentClass(refName));
      }
      if (_isObjectLike(target)) return const IrJsonMap();
      return _typeOf(target,
          owner: owner, prop: prop, kind: kind, group: group);
    }
    if (node.containsKey('allOf')) {
      final parts = (node['allOf'] as List).cast<JsonMap>();
      final substantive = parts.where(_isSubstantive).toList();
      if (substantive.length == 1) {
        return _typeOf(substantive.single,
            owner: owner, prop: prop, kind: kind, group: group);
      }
      return _inlineObject(_mergeShape(node, kind: kind),
          owner: owner, prop: prop, kind: kind, group: group);
    }
    for (final key in const ['oneOf', 'anyOf']) {
      if (node.containsKey(key)) {
        final alternatives = (node[key] as List).cast<JsonMap>();
        if (alternatives.length == 1) {
          return _typeOf(alternatives.single,
              owner: owner, prop: prop, kind: kind, group: group);
        }
        if (alternatives.every(_isObjectLike)) {
          if (!alternatives.any(_hasProperties)) return const IrJsonMap();
          return _inlineObject(_mergeShape(node, kind: kind),
              owner: owner, prop: prop, kind: kind, group: group);
        }
        if (alternatives.every((a) => spec.deref(a)['type'] == 'array')) {
          return const IrList(IrJson());
        }
        return const IrJson();
      }
    }
    final enumValues = node['enum'];
    final type = node['type'];
    if (enumValues is List && (type == null || type == 'string')) {
      final values = enumValues.whereType<String>().toList();
      if (values.length != enumValues.length) return const IrJson();
      if (values.length <= 1) return const IrString();
      return IrEnumRef(
          _inlineEnum(node, values, owner: owner, prop: prop, group: group));
    }
    switch (type) {
      case 'string':
        if (node['format'] == 'binary' && kind == ClassKind.request) {
          return const IrFile();
        }
        return const IrString();
      case 'integer':
        return const IrInt();
      case 'number':
        return const IrDouble();
      case 'boolean':
        return const IrBool();
      case 'array':
        final items = node['items'];
        if (items is! JsonMap || items.isEmpty) return const IrList(IrJson());
        return IrList(_typeOf(items,
            owner: owner, prop: '${prop}Item', kind: kind, group: group));
      case 'object':
        if (node.containsKey('properties') && !_isFreeFormMap(node)) {
          return _inlineObject(node,
              owner: owner, prop: prop, kind: kind, group: group);
        }
        return const IrJsonMap();
      default:
        if (node.containsKey('properties') && !_isFreeFormMap(node)) {
          return _inlineObject(node,
              owner: owner, prop: prop, kind: kind, group: group);
        }
        return const IrJson();
    }
  }

  bool _isSubstantive(JsonMap part) {
    final resolved = spec.deref(part);
    return resolved.keys.any((key) => !const {
          'description',
          'title',
          'example',
          'examples',
          'nullable',
          'deprecated'
        }.contains(key));
  }

  IrType _inlineObject(
    JsonMap node, {
    required String owner,
    required String prop,
    required ClassKind kind,
    required String group,
  }) {
    final className = _classFrom(node, '$owner${pascalCase(prop)}',
        kind: kind, group: group, origin: '$owner.$prop');
    return IrRef(className);
  }

  String _inlineEnum(
    JsonMap node,
    List<String> values, {
    required String owner,
    required String prop,
    required String group,
  }) {
    var enumName = '$owner${pascalCase(prop)}';
    final structure = values.join(' ');
    while (_enums.containsKey(enumName) &&
        _enumStructures[enumName] != structure) {
      enumName = '${enumName}Alt';
    }
    if (!_enums.containsKey(enumName)) {
      final dartNames = <String>{};
      final entries = <EnumValueIr>[];
      for (final value in values) {
        var dartName = enumValueName(value);
        while (!dartNames.add(dartName)) {
          dartName = '${dartName}_';
        }
        entries.add(EnumValueIr(wire: value, dartName: dartName));
      }
      _enumStructures[enumName] = structure;
      _enums[enumName] = EnumIr(
        enumName: enumName,
        group: group,
        values: entries,
        docs: _docOf(node),
      );
    }
    return enumName;
  }

  static const Set<String> _cosmeticKeys = {
    'description',
    'title',
    'example',
    'examples',
    'default',
    'minLength',
    'maxLength',
    'minimum',
    'maximum',
    'minItems',
    'maxItems',
    'nullable',
    'deprecated',
    'readOnly',
    'writeOnly',
    'pattern',
    'uniqueItems',
    'x-codegen-request-body-name',
  };

  String _structure(Object? node) {
    if (node is JsonMap) {
      final keys = node.keys
          .where((key) => !_cosmeticKeys.contains(key))
          .toList()
        ..sort();
      return '{${keys.map((key) => '"$key":${_structure(node[key])}').join(',')}}';
    }
    if (node is List) return '[${node.map(_structure).join(',')}]';
    return node is String ? '"$node"' : '$node';
  }

  String? _docOf(JsonMap node) {
    final description = node['description'];
    if (description is String && description.trim().isNotEmpty) {
      return description;
    }
    final title = node['title'];
    if (title is String && title.trim().isNotEmpty) return title;
    return null;
  }

  NamespaceIr _namespaceFor(String name) => _namespaces.putIfAbsent(
        name,
        () => NamespaceIr(name: name, className: 'Brevo${pascalCase(name)}'),
      );

  void _resolveOperation(String key) {
    final upstream = resources.operations[key]!;
    final operation = spec.operation(key);
    final space = key.indexOf(' ');
    final verb = key.substring(0, space);
    final path = key.substring(space + 1);
    final namespace = _namespaceFor(upstream.namespace);
    final group = upstream.namespace;
    final requestName =
        upstream.requestType ?? '${pascalCase(upstream.method)}Request';

    final pathParams = <ParamIr>[];
    final queryParams = <ParamIr>[];
    for (final raw
        in ((operation['parameters'] as List?) ?? const []).cast<JsonMap>()) {
      final name = raw['name'] as String;
      final schema =
          spec.deref((raw['schema'] as JsonMap?) ?? const {'type': 'string'});
      final isPath = raw['in'] == 'path';
      final type = _paramType(schema,
          owner: requestName, prop: name, group: group, isPath: isPath);
      final param = ParamIr(
        wireName: name,
        dartName: paramName(name),
        type: type,
        required: isPath || raw['required'] == true,
        docs: _docOf(raw),
        defaultValue: schema['default'],
      );
      (isPath ? pathParams : queryParams).add(param);
    }
    final orderedPathParams = <ParamIr>[];
    for (final match in RegExp(r'\{([^}]+)\}').allMatches(path)) {
      final placeholder = match.group(1)!;
      orderedPathParams.add(pathParams.firstWhere(
        (param) => param.wireName == placeholder,
        orElse: () =>
            throw StateError('$key: path parameter $placeholder is undeclared'),
      ));
    }
    if (upstream.queryOrder.isNotEmpty) {
      final order = upstream.queryOrder;
      queryParams.sort((a, b) {
        final ai = order.indexOf(a.wireName);
        final bi = order.indexOf(b.wireName);
        return (ai == -1 ? order.length : ai)
            .compareTo(bi == -1 ? order.length : bi);
      });
    }
    final usedNames = {for (final p in orderedPathParams) p.dartName};
    for (var i = 0; i < queryParams.length; i++) {
      var candidate = queryParams[i].dartName;
      while (!usedNames.add(candidate)) {
        candidate = '${candidate}Query';
      }
      if (candidate != queryParams[i].dartName) {
        final q = queryParams[i];
        queryParams[i] = ParamIr(
          wireName: q.wireName,
          dartName: candidate,
          type: q.type,
          required: q.required,
          docs: q.docs,
          defaultValue: q.defaultValue,
        );
      }
    }

    String? bodyClass;
    var bodyRequired = false;
    final requestBody = operation['requestBody'] as JsonMap?;
    if (requestBody != null) {
      bodyRequired = requestBody['required'] == true;
      final content = requestBody['content'] as JsonMap;
      final mediaType = content.keys.first;
      final schemaNode = (content[mediaType] as JsonMap)['schema'] as JsonMap;
      final multipart = mediaType.startsWith('multipart/');
      final refName = spec.refName(schemaNode);
      if (refName != null) {
        bodyClass = _componentClass(refName);
      } else {
        final merged = _mergeShape(schemaNode, kind: ClassKind.request);
        if (!merged.containsKey('properties')) {
          throw StateError('$key: request body has no properties');
        }
        bodyClass = _classFrom(merged, requestName,
            kind: ClassKind.request,
            group: group,
            origin: key,
            multipart: multipart);
      }
    }

    final response = _response(key, operation, upstream, group);
    final paged = _pagedFor(queryParams, response);

    namespace.operations.add(OperationIr(
      key: key,
      namespace: upstream.namespace,
      methodName: upstream.method,
      httpMethod: verb,
      pathTemplate: path,
      pathParams: orderedPathParams,
      queryParams: queryParams,
      bodyClass: bodyClass,
      bodyRequired: bodyRequired,
      response: response,
      paged: paged,
      docs: [operation['summary'], operation['description']]
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join('\n\n'),
      deprecated: operation['deprecated'] == true,
    ));
  }

  IrType _paramType(
    JsonMap schema, {
    required String owner,
    required String prop,
    required String group,
    required bool isPath,
  }) {
    for (final key in const ['oneOf', 'anyOf']) {
      if (schema.containsKey(key)) return const IrJson();
    }
    final enumValues = schema['enum'];
    final type = schema['type'];
    if (enumValues is List && enumValues.isNotEmpty) {
      if (type == 'boolean') return const IrBool();
      if (type == 'integer') return const IrInt();
      final values = enumValues.whereType<String>().toList();
      if (values.length == enumValues.length && values.length > 1) {
        return IrEnumRef(_inlineEnum(schema, values,
            owner: owner, prop: prop, group: group));
      }
    }
    switch (type) {
      case 'string':
        return const IrString();
      case 'integer':
        return const IrInt();
      case 'number':
        return const IrDouble();
      case 'boolean':
        return const IrBool();
      case 'array':
        final items = spec
            .deref((schema['items'] as JsonMap?) ?? const {'type': 'string'});
        return IrList(_paramType(items,
            owner: owner, prop: '${prop}Item', group: group, isPath: isPath));
      default:
        return isPath ? const IrString() : const IrJson();
    }
  }

  ResponseIr _response(
      String key, JsonMap operation, UpstreamOperation upstream, String group) {
    final responses = operation['responses'] as JsonMap;
    final successCodes =
        responses.keys.where((code) => code.startsWith('2')).toList()..sort();
    if (successCodes.isEmpty) throw StateError('$key has no 2xx response');
    final withContent = <String, JsonMap>{};
    for (final code in successCodes) {
      final content = (responses[code] as JsonMap)['content'] as JsonMap?;
      if (content == null || content.isEmpty) continue;
      final jsonMedia = content['application/json'] as JsonMap?;
      if (jsonMedia != null && jsonMedia['schema'] == null) continue;
      withContent[code] = content;
    }
    if (withContent.isEmpty) return const VoidResponse();
    if (withContent.values
        .any((content) => !content.containsKey('application/json'))) {
      if (withContent.length == 1) return const BytesResponse();
      throw StateError('$key mixes JSON and non-JSON success responses');
    }
    final schemas = <JsonMap>[
      for (final content in withContent.values)
        (content['application/json'] as JsonMap)['schema'] as JsonMap,
    ];
    final responseName =
        upstream.responseType ?? '${pascalCase(upstream.method)}Response';
    if (schemas.length == 1) {
      final schema = schemas.single;
      final refName = spec.refName(schema);
      final resolved = spec.deref(schema);
      if (refName != null && resolved['type'] != 'array') {
        return ObjectResponse(_componentClass(refName));
      }
      if (resolved['type'] == 'array') {
        final items = resolved['items'] as JsonMap?;
        if (items == null) return const ListResponse(IrJson());
        final itemName = pascalCase(refName != null
            ? '${refName}Item'
            : responseName.endsWith('[]')
                ? responseName.substring(0, responseName.length - 2)
                : '${responseName}Item');
        final itemRef = spec.refName(items);
        if (itemRef != null) {
          return ListResponse(IrRef(_componentClass(itemRef)));
        }
        if (_isObjectLike(items) && _hasProperties(items)) {
          return ListResponse(IrRef(_classFrom(
              _mergeShape(items, kind: ClassKind.model), itemName,
              kind: ClassKind.model, group: group, origin: key)));
        }
        return ListResponse(_typeOf(items,
            owner: itemName,
            prop: 'Item',
            kind: ClassKind.model,
            group: group));
      }
      if (resolved['type'] == 'string') return const VoidResponse();
      if (!_isObjectLike(resolved)) {
        throw StateError('$key: unsupported response type ${resolved['type']}');
      }
      final merged = _mergeShape(resolved, kind: ClassKind.model);
      if (!merged.containsKey('properties')) {
        return ObjectResponse(_classFrom(
            const {'type': 'object', 'properties': <String, Object?>{}},
            _responseClassName(responseName),
            kind: ClassKind.model,
            group: group,
            origin: key));
      }
      return ObjectResponse(_classFrom(merged, _responseClassName(responseName),
          kind: ClassKind.model, group: group, origin: key));
    }
    final merged = _mergeAll(
      [
        for (final schema in schemas) _mergeShape(schema, kind: ClassKind.model)
      ],
      requireAll: false,
    );
    return ObjectResponse(_classFrom(merged, _responseClassName(responseName),
        kind: ClassKind.model, group: group, origin: key));
  }

  String _responseClassName(String upstreamName) {
    final name = pascalCase(upstreamName.replaceAll('[]', ''));
    final component = spec.schemas.keys
        .where((schema) => pascalCase(schema) == name)
        .toList();
    return component.isEmpty ? name : '${name}Response';
  }

  PagedIr? _pagedFor(List<ParamIr> queryParams, ResponseIr response) {
    if (response is! ObjectResponse) return null;
    final hasLimit =
        queryParams.any((q) => q.wireName == 'limit' && q.type is IrInt);
    final hasOffset =
        queryParams.any((q) => q.wireName == 'offset' && q.type is IrInt);
    if (!hasLimit || !hasOffset) return null;
    final responseClass = _classes[response.className]!;
    final count = responseClass.fields
        .where((f) => f.wireName == 'count' && f.type is IrInt)
        .toList();
    final lists = responseClass.fields
        .where((f) => f.type is IrList && (f.type as IrList).element is IrRef)
        .toList();
    if (count.length != 1 || lists.length != 1) return null;
    final element = (lists.single.type as IrList).element as IrRef;
    return PagedIr(
        itemClass: element.className, listWireName: lists.single.wireName);
  }

  void _resolveMockCases() {
    final byKey = <String, OperationIr>{
      for (final namespace in _namespaces.values)
        for (final op in namespace.operations)
          '${op.httpMethod} ${_normalise(op.pathTemplate)}': op,
    };
    for (final mapping in mappings.mappings) {
      final request = mapping['request']! as JsonMap;
      final template = request['urlPathTemplate'] as String;
      final normalised = '${request['method']} ${_normalise(template)}';
      final op = byKey[normalised];
      if (op == null) throw StateError('mapping $normalised has no operation');
      final pathParams = <String, String>{};
      final specNames = RegExp(r'\{([^}]+)\}')
          .allMatches(op.pathTemplate)
          .map((m) => m.group(1)!)
          .toList();
      final mappingNames = RegExp(r'\{([^}]+)\}')
          .allMatches(template)
          .map((m) => m.group(1)!)
          .toList();
      final matchers = (request['pathParameters'] as JsonMap?) ?? const {};
      for (var i = 0; i < specNames.length; i++) {
        final matcher = matchers[mappingNames[i]] as JsonMap?;
        if (matcher == null || matcher['equalTo'] is! String) {
          throw StateError(
              '${op.key}: mapping has no equalTo for path parameter ${mappingNames[i]}');
        }
        pathParams[specNames[i]] = matcher['equalTo'] as String;
      }
      final queryParams = <String, String>{};
      for (final entry
          in ((request['queryParameters'] as JsonMap?) ?? const {}).entries) {
        final matcher = entry.value as JsonMap;
        if (!op.queryParams.any((q) => q.wireName == entry.key)) {
          throw StateError(
              '${op.key}: mapping queries ${entry.key}, which the spec lacks');
        }
        queryParams[entry.key] = matcher['equalTo'] as String;
      }
      final response = mapping['response']! as JsonMap;
      _mockCases.add(MockCaseIr(
        operationKey: op.key,
        pathParams: pathParams,
        queryParams: queryParams,
        responseBody: response['body'],
        status: response['status'] as int,
      ));
    }
  }

  static String _normalise(String path) {
    var normalised = path.replaceAll(RegExp(r'\{[^}]*\}'), '{}');
    if (!normalised.startsWith('/')) normalised = '/$normalised';
    return normalised;
  }
}
