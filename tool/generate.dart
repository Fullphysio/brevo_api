import 'dart:io';

import 'emit/emitters.dart';
import 'ir/model.dart';
import 'ir/resolve.dart';
import 'ir/spec.dart';

const List<String> _managedDirectories = [
  'lib/src/generated',
  'test/generated'
];

Future<void> main(List<String> arguments) async {
  final spec = OpenApiSpec.load('tool/spec/brevo-openapi.json');
  final resources = ResourceMap.load('tool/spec/resources.yaml');
  final mappings = WireMockMappings.load('tool/mock/wiremock-mappings.json');
  final digest = File('tool/spec/SPEC_SHA256').readAsStringSync().trim();
  final ir = Resolver(spec, resources, mappings, digest).resolve();

  if (arguments.contains('--report')) {
    _report(ir);
    return;
  }

  final files = Emitter(ir).emitAll();
  final staging = Directory.systemTemp.createTempSync('brevo_api_generate_');
  try {
    for (final file in files) {
      final target = File('${staging.path}/${file.path}')
        ..createSync(recursive: true);
      target.writeAsStringSync(file.content);
    }
    final format = await Process.run('dart',
        ['format', '--language-version=${_languageVersion()}', staging.path]);
    if (format.exitCode != 0) {
      stderr.writeln(format.stdout);
      stderr.writeln(format.stderr);
      throw StateError('dart format failed on the generated output');
    }
    final generated = <String, String>{
      for (final file in files)
        file.path: File('${staging.path}/${file.path}').readAsStringSync(),
    };

    if (arguments.contains('--check')) {
      final drift = _drift(generated);
      if (drift.isEmpty) {
        stdout.writeln(
            'Generated code is up to date (${generated.length} files).');
        return;
      }
      stderr.writeln('Generated code is out of date:');
      drift.forEach(stderr.writeln);
      exitCode = 1;
      return;
    }

    for (final directory in _managedDirectories) {
      final dir = Directory(directory);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    for (final entry in generated.entries) {
      File(entry.key)
        ..createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    stdout.writeln('Wrote ${generated.length} generated files.');
  } finally {
    staging.deleteSync(recursive: true);
  }
}

String _languageVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(r'''sdk:\s*['"]?\^(\d+\.\d+)''').firstMatch(pubspec);
  if (match == null) {
    throw StateError(
        'pubspec.yaml has no ^X.Y sdk constraint to derive the language version from');
  }
  return match.group(1)!;
}

List<String> _drift(Map<String, String> generated) {
  final drift = <String>[];
  final existing = <String>{};
  for (final directory in _managedDirectories) {
    final dir = Directory(directory);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true).whereType<File>()) {
      existing.add(entity.path);
    }
  }
  for (final entry in generated.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      drift.add('  missing: ${entry.key}');
    } else if (file.readAsStringSync() != entry.value) {
      drift.add('  changed: ${entry.key}');
    }
  }
  for (final path in existing) {
    if (!generated.containsKey(path)) drift.add('  stale:   $path');
  }
  return drift..sort();
}

void _report(GeneratorIr ir) {
  final requests =
      ir.classes.values.where((c) => c.kind == ClassKind.request).length;
  stdout.writeln(
      'classes: ${ir.classes.length} (requests: $requests, multipart: ${ir.classes.values.where((c) => c.multipart).length})');
  stdout.writeln('enums: ${ir.enums.length}');
  var operations = 0;
  var paged = 0;
  for (final namespace in ir.namespaces.values) {
    operations += namespace.operations.length;
    paged += namespace.operations.where((op) => op.paged != null).length;
    stdout.writeln(
        '${namespace.name} -> ${namespace.className} (${namespace.operations.length} ops)');
  }
  stdout.writeln('operations: $operations (paged: $paged)');
  stdout.writeln('mock cases: ${ir.mockCases.length}');
  final groups = <String, int>{};
  for (final c in ir.classes.values) {
    groups[c.group] = (groups[c.group] ?? 0) + 1;
  }
  stdout.writeln('--- classes per group ---');
  for (final entry in groups.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    stdout.writeln('${entry.key}: ${entry.value}');
  }
  stdout.writeln('--- enums ---');
  for (final e in ir.enums.values) {
    stdout.writeln(
        '${e.enumName} [${e.group}]: ${e.values.map((v) => v.dartName).join(', ')}');
  }
  stdout.writeln('--- classes ---');
  for (final c in ir.classes.values) {
    stdout.writeln(
        '${c.className} [${c.kind.name}${c.multipart ? ', multipart' : ''}, ${c.group}] ${c.fields.length} fields${c.origin == null ? '' : ' <- ${c.origin}'}');
  }
}
