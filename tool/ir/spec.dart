import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

typedef JsonMap = Map<String, Object?>;

const Set<String> httpMethods = {'get', 'post', 'put', 'patch', 'delete'};

final class OpenApiSpec {
  OpenApiSpec(this.root);

  factory OpenApiSpec.load(String path) =>
      OpenApiSpec(json.decode(File(path).readAsStringSync()) as JsonMap);

  final JsonMap root;

  JsonMap get schemas =>
      ((root['components']! as JsonMap)['schemas'] ?? <String, Object?>{})
          as JsonMap;
  JsonMap get paths => root['paths']! as JsonMap;

  String? refName(JsonMap node) {
    final ref = node[r'$ref'];
    if (ref is! String) return null;
    const prefix = '#/components/schemas/';
    if (!ref.startsWith(prefix)) return null;
    return ref.substring(prefix.length);
  }

  JsonMap schema(String name) {
    final node = schemas[name];
    if (node == null) throw StateError('unknown schema $name');
    return node as JsonMap;
  }

  JsonMap deref(JsonMap node) {
    var current = node;
    for (var i = 0; i < 10; i++) {
      final name = refName(current);
      if (name == null) return current;
      current = schema(name);
    }
    throw StateError('\$ref chain too deep at $node');
  }

  List<String> operationKeys() {
    final keys = <String>[];
    for (final pathEntry in paths.entries) {
      for (final method in (pathEntry.value as JsonMap).keys) {
        if (!httpMethods.contains(method)) continue;
        keys.add('${method.toUpperCase()} ${pathEntry.key}');
      }
    }
    return keys..sort();
  }

  JsonMap operation(String key) {
    final space = key.indexOf(' ');
    final verb = key.substring(0, space).toLowerCase();
    final path = key.substring(space + 1);
    final item = paths[path];
    if (item == null) throw StateError('unknown path $path');
    final op = (item as JsonMap)[verb];
    if (op == null) throw StateError('unknown operation $key');
    return op as JsonMap;
  }
}

final class UpstreamOperation {
  const UpstreamOperation({
    required this.namespace,
    required this.method,
    required this.requestType,
    required this.responseType,
    required this.queryOrder,
  });
  final String namespace;
  final String method;
  final String? requestType;
  final String? responseType;
  final List<String> queryOrder;
}

final class ResourceMap {
  ResourceMap({required this.operations, required this.upstreamTag});

  factory ResourceMap.load(String path) {
    final doc = loadYaml(File(path).readAsStringSync()) as YamlMap;
    final operations = <String, UpstreamOperation>{};
    for (final entry in (doc['operations'] as YamlMap).entries) {
      final value = entry.value as YamlMap;
      final response = value['response'] as String;
      operations[entry.key as String] = UpstreamOperation(
        namespace: value['namespace'] as String,
        method: value['method'] as String,
        requestType: value['request'] as String?,
        responseType: response == 'void' ? null : response,
        queryOrder:
            ((value['query'] as YamlList?) ?? YamlList()).cast<String>(),
      );
    }
    return ResourceMap(
      operations: operations,
      upstreamTag: (doc['upstream'] as YamlMap)['tag'] as String,
    );
  }

  final Map<String, UpstreamOperation> operations;
  final String upstreamTag;
}

final class WireMockMappings {
  WireMockMappings(this.mappings);

  factory WireMockMappings.load(String path) {
    final doc = json.decode(File(path).readAsStringSync()) as JsonMap;
    return WireMockMappings(
        (doc['mappings']! as List).cast<JsonMap>().toList(growable: false));
  }

  final List<JsonMap> mappings;
}
