import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../operation_key.dart';

/// Vendors the Brevo OpenAPI specification into `tool/spec/`, recording its
/// digest and the fetch date, and writes `CHANGELOG_SPEC.md` describing what
/// changed since the previously vendored copy.
///
/// Usage: `dart run tool/spec/update_spec.dart [--from <file-or-url>]`
///
/// Brevo publishes the specification at an unversioned URL, so the digest in
/// `SPEC_SHA256` is the only durable identity of what was generated from.
Future<void> main(List<String> arguments) async {
  final source = _parseSource(arguments);
  final text = await _fetch(source);
  final decoded = _toJson(loadYaml(text, sourceUrl: Uri.parse(source)));
  if (decoded is! Map<String, Object?>) {
    throw StateError('The specification is not a YAML/JSON object.');
  }
  for (final key in const ['openapi', 'paths', 'components']) {
    final value = decoded[key];
    if (value == null || (value is Map && value.isEmpty)) {
      throw StateError(
        'The specification has no "$key" section; refusing to vendor.',
      );
    }
  }

  final canonical =
      '${const JsonEncoder.withIndent('  ').convert(_sortKeys(decoded))}\n';
  final digest = sha256.convert(utf8.encode(canonical)).toString();
  final fetchedAt = DateTime.now().toUtc().toIso8601String();

  final previousSpec = File('tool/spec/brevo-openapi.json');
  final previousDate = File('tool/spec/SPEC_FETCHED_AT');
  if (previousSpec.existsSync() && previousDate.existsSync()) {
    final previous =
        json.decode(previousSpec.readAsStringSync()) as Map<String, Object?>;
    File('tool/spec/CHANGELOG_SPEC.md').writeAsStringSync(
      _changelog(
          previous, decoded, previousDate.readAsStringSync().trim(), fetchedAt),
    );
  }

  File('tool/spec/brevo-openapi.json').writeAsStringSync(canonical);
  File('tool/spec/SPEC_SHA256').writeAsStringSync('$digest\n');
  File('tool/spec/SPEC_FETCHED_AT').writeAsStringSync('$fetchedAt\n');
  File('tool/spec/SPEC_SOURCE').writeAsStringSync('$source\n');

  final paths = decoded['paths']! as Map<String, Object?>;
  stdout.writeln(
    'Vendored tool/spec/brevo-openapi.json (${decoded['openapi']}, '
    'info.version ${(decoded['info'] as Map<String, Object?>?)?['version']}): '
    '${paths.length} paths, ${_operations(decoded).length} operations, '
    '${_schemas(decoded).length} component schemas ($digest).',
  );
}

const String defaultSpecUrl =
    'https://api.brevo.com/v3/swagger_definition_v3.yml';

String _parseSource(List<String> arguments) {
  final index = arguments.indexOf('--from');
  if (index == -1) return defaultSpecUrl;
  if (index + 1 >= arguments.length) {
    throw ArgumentError('--from needs a file path or URL');
  }
  return arguments[index + 1];
}

Future<String> _fetch(String source) async {
  final uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw StateError(
        'Failed to download the specification from $source: '
        'HTTP ${response.statusCode}.',
      );
    }
    return utf8.decode(response.bodyBytes);
  }
  return File(source).readAsStringSync();
}

Object? _toJson(Object? node) {
  if (node is YamlMap) {
    return <String, Object?>{
      for (final entry in node.nodes.entries)
        '${(entry.key as YamlNode).value}': _toJson(entry.value.value),
    };
  }
  if (node is YamlList) {
    return [for (final item in node.nodes) _toJson(item.value)];
  }
  if (node is YamlScalar) return _toJson(node.value);
  return node;
}

Set<String> _operations(Map<String, Object?> spec) => {
      for (final entry in (spec['paths']! as Map<String, Object?>).entries)
        for (final method in (entry.value as Map<String, Object?>).keys)
          if (httpMethods.contains(method))
            '${method.toUpperCase()} ${entry.key}',
    };

Map<String, Object?> _schemas(Map<String, Object?> spec) =>
    ((spec['components']! as Map<String, Object?>)['schemas'] ?? const {})
        as Map<String, Object?>;

Map<String, List<String>> _enumValues(Map<String, Object?> spec) {
  final result = <String, List<String>>{};
  void walk(Object? node, String path) {
    if (node is! Map<String, Object?>) return;
    final values = node['enum'];
    if (values is List) {
      result[path] = values.map((value) => '$value').toList();
    }
    final properties = node['properties'];
    if (properties is Map<String, Object?>) {
      for (final entry in properties.entries) {
        walk(entry.value, '$path.${entry.key}');
      }
    }
    walk(node['items'], '$path[]');
    walk(node['additionalProperties'], '$path{}');
    for (final key in const ['allOf', 'oneOf', 'anyOf']) {
      final parts = node[key];
      if (parts is List) {
        for (var i = 0; i < parts.length; i++) {
          walk(parts[i], '$path<$key $i>');
        }
      }
    }
  }

  for (final entry in _schemas(spec).entries) {
    walk(entry.value, entry.key);
  }
  for (final pathEntry in (spec['paths']! as Map<String, Object?>).entries) {
    for (final opEntry in (pathEntry.value as Map<String, Object?>).entries) {
      if (!httpMethods.contains(opEntry.key)) continue;
      final op = opEntry.value as Map<String, Object?>;
      final label = '${opEntry.key.toUpperCase()} ${pathEntry.key}';
      final parameters = op['parameters'];
      if (parameters is List) {
        for (final parameter in parameters.whereType<Map<String, Object?>>()) {
          walk(parameter['schema'], '$label ?${parameter['name']}');
        }
      }
      final body = op['requestBody'];
      if (body is Map<String, Object?>) {
        final content = body['content'];
        if (content is Map<String, Object?>) {
          for (final media
              in content.values.whereType<Map<String, Object?>>()) {
            walk(media['schema'], '$label body');
          }
        }
      }
      final responses = op['responses'];
      if (responses is Map<String, Object?>) {
        for (final response in responses.entries) {
          final content = (response.value as Map<String, Object?>?)?['content'];
          if (content is Map<String, Object?>) {
            for (final media
                in content.values.whereType<Map<String, Object?>>()) {
              walk(media['schema'], '$label ${response.key}');
            }
          }
        }
      }
    }
  }
  return result;
}

Map<String, Set<String>> _requiredFields(Map<String, Object?> spec) {
  final result = <String, Set<String>>{};
  void walk(Object? node, String path) {
    if (node is! Map<String, Object?>) return;
    final required = node['required'];
    if (required is List) {
      result[path] = required.map((value) => '$value').toSet();
    }
    final properties = node['properties'];
    if (properties is Map<String, Object?>) {
      for (final entry in properties.entries) {
        walk(entry.value, '$path.${entry.key}');
      }
    }
    walk(node['items'], '$path[]');
    for (final key in const ['allOf', 'oneOf', 'anyOf']) {
      final parts = node[key];
      if (parts is List) {
        for (var i = 0; i < parts.length; i++) {
          walk(parts[i], '$path<$key $i>');
        }
      }
    }
  }

  for (final entry in _schemas(spec).entries) {
    walk(entry.value, entry.key);
  }
  return result;
}

String _changelog(Map<String, Object?> previous, Map<String, Object?> next,
    String previousDate, String nextDate) {
  final buffer = StringBuffer()
    ..writeln('# Specification changes')
    ..writeln()
    ..writeln('Vendored copy fetched $previousDate → $nextDate.')
    ..writeln();

  void section(String title, Iterable<String> added, Iterable<String> removed) {
    final addedList = added.toList()..sort();
    final removedList = removed.toList()..sort();
    if (addedList.isEmpty && removedList.isEmpty) return;
    buffer
      ..writeln('## $title')
      ..writeln();
    for (final item in addedList) {
      buffer.writeln('- added: $item');
    }
    for (final item in removedList) {
      buffer.writeln('- removed: $item');
    }
    buffer.writeln();
  }

  final previousOps = _operations(previous);
  final nextOps = _operations(next);
  section('Operations', nextOps.difference(previousOps),
      previousOps.difference(nextOps));

  final previousSchemas = _schemas(previous).keys.toSet();
  final nextSchemas = _schemas(next).keys.toSet();
  section('Component schemas', nextSchemas.difference(previousSchemas),
      previousSchemas.difference(nextSchemas));

  final previousEnums = _enumValues(previous);
  final nextEnums = _enumValues(next);
  final enumAdded = <String>[];
  final enumRemoved = <String>[];
  for (final path in {...previousEnums.keys, ...nextEnums.keys}) {
    final before = previousEnums[path]?.toSet() ?? const <String>{};
    final after = nextEnums[path]?.toSet() ?? const <String>{};
    for (final value in after.difference(before)) {
      enumAdded.add('$path: $value');
    }
    for (final value in before.difference(after)) {
      enumRemoved.add('$path: $value');
    }
  }
  section('Enum values', enumAdded, enumRemoved);

  final previousRequired = _requiredFields(previous);
  final nextRequired = _requiredFields(next);
  final requiredAdded = <String>[];
  final requiredRemoved = <String>[];
  for (final path in {...previousRequired.keys, ...nextRequired.keys}) {
    final before = previousRequired[path] ?? const <String>{};
    final after = nextRequired[path] ?? const <String>{};
    for (final field in after.difference(before)) {
      requiredAdded.add('$path.$field');
    }
    for (final field in before.difference(after)) {
      requiredRemoved.add('$path.$field');
    }
  }
  section('Required fields', requiredAdded, requiredRemoved);

  if (buffer.toString().trim().endsWith('.')) {
    buffer.writeln('No operation, schema, enum or required-field changes.');
  }
  return buffer.toString();
}

Object? _sortKeys(Object? node) {
  if (node is Map<String, Object?>) {
    final keys = node.keys.toList()..sort();
    return <String, Object?>{for (final key in keys) key: _sortKeys(node[key])};
  }
  if (node is List) return node.map(_sortKeys).toList();
  return node;
}
