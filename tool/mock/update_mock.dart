import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../operation_key.dart';

/// Vendors the WireMock mappings Brevo's Python SDK is tested against into
/// `tool/mock/`, recording their digest and the release they came from, and
/// checks that they cover exactly the operations of the vendored
/// specification.
///
/// Usage: `dart run tool/mock/update_mock.dart --tag v5.0.2`
///
/// The tag is a release of `getbrevo/brevo-python`; its
/// `wiremock/wiremock-mappings.json` is generated from the same API
/// definition as the Node SDK this package ports.
Future<void> main(List<String> arguments) async {
  final tag = _parseTag(arguments);
  final url = Uri.parse(
      'https://raw.githubusercontent.com/getbrevo/brevo-python/$tag/wiremock/wiremock-mappings.json');
  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to download the WireMock mappings at tag "$tag" from $url: '
      'HTTP ${response.statusCode}. Confirm the tag exists in '
      'https://github.com/getbrevo/brevo-python/tags.',
    );
  }
  final decoded = json.decode(utf8.decode(response.bodyBytes));
  if (decoded is! Map<String, Object?> || decoded['mappings'] is! List) {
    throw StateError('The mappings file has no "mappings" list.');
  }
  final mappings = (decoded['mappings']! as List).cast<Map<String, Object?>>();

  final spec =
      json.decode(File('tool/spec/brevo-openapi.json').readAsStringSync())
          as Map<String, Object?>;
  final specKeys = <String>{
    for (final entry in (spec['paths']! as Map<String, Object?>).entries)
      for (final method in (entry.value as Map<String, Object?>).keys)
        if (httpMethods.contains(method))
          '${method.toUpperCase()} ${normalisePathTemplate(entry.key)}',
  };
  final mappingKeys = <String>{};
  for (final mapping in mappings) {
    final request = mapping['request']! as Map<String, Object?>;
    final template = request['urlPathTemplate'] ?? request['urlPath'];
    if (template is! String) {
      throw StateError('Mapping ${mapping['name']} has no urlPathTemplate.');
    }
    final key = '${request['method']} ${normalisePathTemplate(template)}';
    if (!mappingKeys.add(key)) {
      throw StateError('Two mappings address $key.');
    }
  }
  final onlyInMappings = mappingKeys.difference(specKeys).toList()..sort();
  final onlyInSpec = specKeys.difference(mappingKeys).toList()..sort();
  if (onlyInMappings.isNotEmpty || onlyInSpec.isNotEmpty) {
    final buffer = StringBuffer('Mappings and specification disagree:\n');
    for (final key in onlyInMappings) {
      buffer.writeln('  only in the mappings: $key');
    }
    for (final key in onlyInSpec) {
      buffer.writeln('  only in the spec:     $key');
    }
    throw StateError(buffer.toString());
  }

  final canonical = '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
  final digest = sha256.convert(utf8.encode(canonical)).toString();
  File('tool/mock/wiremock-mappings.json').writeAsStringSync(canonical);
  File('tool/mock/MAPPINGS_SHA256').writeAsStringSync('$digest\n');
  File('tool/mock/MAPPINGS_VERSION').writeAsStringSync('$tag\n');
  stdout.writeln(
      'Vendored tool/mock/wiremock-mappings.json from brevo-python $tag: ${mappings.length} mappings, all matching the specification ($digest).');
}

String _parseTag(List<String> arguments) {
  final index = arguments.indexOf('--tag');
  if (index == -1 || index + 1 >= arguments.length) {
    throw ArgumentError('Usage: update_mock.dart --tag vX.Y.Z');
  }
  final tag = arguments[index + 1];
  if (!RegExp(r'^v\d+\.\d+\.\d+').hasMatch(tag)) {
    throw ArgumentError('"$tag" is not a release tag like v5.0.2');
  }
  return tag;
}

String normalisePathTemplate(String path) {
  var normalised = path.replaceAll(RegExp(r'\{[^}]*\}'), '{}');
  if (!normalised.startsWith('/')) normalised = '/$normalised';
  return normalised;
}
