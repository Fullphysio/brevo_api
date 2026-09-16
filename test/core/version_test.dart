import 'dart:io';

import 'package:brevo_api/src/core/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('brevoApiVersion matches pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(brevoApiVersion, pubspec['version']);
  });
}
