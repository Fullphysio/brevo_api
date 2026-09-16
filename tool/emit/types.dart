import '../ir/model.dart';

String dartType(IrType type) => switch (type) {
      IrString() => 'String',
      IrInt() => 'int',
      IrDouble() => 'double',
      IrBool() => 'bool',
      IrJson() => 'Object?',
      IrJsonMap() => 'Map<String, Object?>',
      IrFile() => 'BrevoFile',
      IrList(:final element) => 'List<${dartType(element)}>',
      IrRef(:final className) => className,
      IrEnumRef(:final enumName) => enumName,
    };

bool defaultsToEmpty(IrType type) => type is IrList || type is IrJsonMap;

/// The declared Dart type of a field: non-null when the class is a request
/// and the spec requires it, or when a model field is a collection that
/// defaults to empty; nullable otherwise. `Object?` is always nullable.
String fieldDartType(FieldIr field, ClassKind kind) {
  if (field.type is IrJson) return 'Object?';
  final base = dartType(field.type);
  if (field.required) return base;
  if (kind == ClassKind.model && defaultsToEmpty(field.type)) return base;
  return '$base?';
}

bool fieldIsNullable(FieldIr field, ClassKind kind) =>
    field.type is IrJson ||
    (!field.required &&
        !(kind == ClassKind.model && defaultsToEmpty(field.type)));

Set<String> referencedTypeNames(IrType type) => switch (type) {
      IrList(:final element) => referencedTypeNames(element),
      IrRef(:final className) => {className},
      IrEnumRef(:final enumName) => {enumName},
      _ => const {},
    };

String dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

String decodeField(FieldIr field, String owner, ClassKind kind) {
  final key = dartStringLiteral(field.wireName);
  final ownerLiteral = dartStringLiteral(owner);
  final expression = decodeValue(field.type, key, owner);
  if (field.required) {
    return switch (field.type) {
      IrString() => 'json.requireString($key, $ownerLiteral)',
      IrInt() => 'json.requireInt($key, $ownerLiteral)',
      IrJson() => 'json[$key]',
      IrList() ||
      IrJsonMap() =>
        'json.containsKey($key) ? $expression : (throw BrevoDecodeException.missingRequiredKey(objectName: $ownerLiteral, key: $key))',
      _ =>
        '$expression ?? (throw BrevoDecodeException.missingRequiredKey(objectName: $ownerLiteral, key: $key))',
    };
  }
  if (kind == ClassKind.request && defaultsToEmpty(field.type)) {
    return 'json.containsKey($key) ? $expression : null';
  }
  return expression;
}

bool needsDecodeException(ClassIr c) => c.fields.any((field) =>
    field.required &&
    field.type is! IrString &&
    field.type is! IrInt &&
    field.type is! IrJson);

String decodeValue(IrType type, String key, String owner) => switch (type) {
      IrString() => 'json.optString($key)',
      IrInt() => 'json.optInt($key)',
      IrDouble() => 'json.optDouble($key)',
      IrBool() => 'json.optBool($key)',
      IrJson() => 'json[$key]',
      IrJsonMap() => 'json.optObjectMap($key)',
      IrFile() => throw StateError('a file field cannot be decoded from JSON'),
      IrRef(:final className) => 'json.optNested($key, $className.fromJson)',
      IrEnumRef(:final enumName) => 'json.optEnum($key, $enumName.fromWire)',
      IrList(:final element) => _decodeList(element, key, owner),
    };

String _decodeList(IrType element, String key, String owner) =>
    switch (element) {
      IrString() => 'json.optStringList($key)',
      IrInt() => 'json.optIntList($key)',
      IrDouble() => 'json.optDoubleList($key)',
      IrBool() => 'json.optBoolList($key)',
      IrJson() => 'json.optList($key, (element) => element)',
      IrJsonMap() =>
        'json.optList($key, (element) => element is Map<String, Object?> ? element : <String, Object?>{})',
      IrFile() => throw StateError('a file list cannot be decoded from JSON'),
      IrRef(:final className) =>
        'json.optObjectList($key, $className.fromJson, objectName: ${dartStringLiteral(owner)})',
      IrEnumRef(:final enumName) =>
        'json.optStringList($key).map($enumName.fromWire).toList(growable: false)',
      IrList(element: final inner) =>
        'json.optList($key, (element) => element is List<Object?> ? ${_decodeInnerList(inner)} : ${_emptyListLiteral(inner)})',
    };

String _decodeInnerList(IrType inner) => switch (inner) {
      IrString() => 'element.whereType<String>().toList(growable: false)',
      IrInt() => 'element.whereType<int>().toList(growable: false)',
      IrDouble() =>
        'element.whereType<num>().map((n) => n.toDouble()).toList(growable: false)',
      IrBool() => 'element.whereType<bool>().toList(growable: false)',
      IrRef(:final className) =>
        'element.whereType<Map<String, Object?>>().map($className.fromJson).toList(growable: false)',
      IrEnumRef(:final enumName) =>
        'element.whereType<String>().map($enumName.fromWire).toList(growable: false)',
      IrJsonMap() =>
        'element.whereType<Map<String, Object?>>().toList(growable: false)',
      _ => 'element',
    };

String _emptyListLiteral(IrType inner) => switch (inner) {
      IrJson() => 'const <Object?>[]',
      _ => 'const <${dartType(inner)}>[]',
    };

String encodeValue(IrType type, String expression) => switch (type) {
      IrRef() => '$expression.toJson()',
      IrEnumRef() => '$expression.value',
      IrList(element: IrRef()) =>
        '[for (final item in $expression) item.toJson()]',
      IrList(element: IrEnumRef()) =>
        '[for (final item in $expression) item.value]',
      IrList(element: IrList(element: IrRef())) =>
        '[for (final inner in $expression) [for (final item in inner) item.toJson()]]',
      _ => expression,
    };

String decodeTopLevel(IrType type, String expression) => switch (type) {
      IrRef(:final className) =>
        '$className.fromJson(brevoRequireJsonObject($expression, objectName: ${dartStringLiteral(className)}))',
      _ => throw StateError('unsupported top-level type ${dartType(type)}'),
    };
