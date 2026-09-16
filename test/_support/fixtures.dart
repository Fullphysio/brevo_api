import 'dart:convert';
import 'dart:io';

Map<String, Object?> loadFixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> casesOf(Map<String, Object?> fixture) =>
    (fixture['cases']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> mapOf(Object? value) => value as Map<String, Object?>;

/// The message `@getbrevo/brevo` builds, minus the leading line that names
/// its JavaScript class — the one line a Dart port cannot reproduce.
String upstreamMessageWithoutClassName(Map<String, Object?> expected) {
  final message = expected['message']! as String;
  final className = expected['className'] as String?;
  if (className != null && message.startsWith('$className\n')) {
    return message.substring(className.length + 1);
  }
  return message;
}
