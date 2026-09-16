import 'package:test/test.dart';

/// Asserts that [output] — what a decoded model's `toJson()` produced —
/// faithfully reproduces the [input] payload it was decoded from.
///
/// The generated decode and mock tiers call every model against real Brevo
/// payloads. Checking only that decoding did not throw would pass a model
/// that read the wrong key, widened a field to the wrong type or silently
/// dropped half the payload, so the assertion here is a round trip instead:
///
/// - every value `toJson()` emitted, at any depth, must equal the value the
///   payload carried for that key, so a swapped or fabricated field fails;
/// - every key of [knownKeys] the payload carried must come back out, so a
///   field decoded under the wrong wire name fails.
///
/// Three differences are legitimate and tolerated. A model omits a field
/// that was absent or `null`, and omits an empty list or map, so absence and
/// emptiness compare equal. JSON has one numeric type, so `250` and `250.0`
/// compare equal. And a payload may carry keys outside [knownKeys] — fields
/// Brevo added after this package was generated — which stay in `raw` rather
/// than in `toJson()`.
void expectJsonRoundTrip(
  Map<String, Object?> input,
  Map<String, Object?> output, {
  required String context,
  Set<String> knownKeys = const <String>{},
}) {
  for (final key in knownKeys) {
    if (_isAbsent(input[key])) {
      continue;
    }
    expect(
      output.containsKey(key),
      isTrue,
      reason: '$context: the payload carried "$key" but toJson() dropped it',
    );
  }
  _expectSame(input, output, context);
}

void _expectSame(Object? input, Object? output, String path) {
  if (output is Map<String, Object?>) {
    expect(
      input,
      isA<Map<String, Object?>>(),
      reason: '$path: toJson() produced an object where the payload had '
          '${input.runtimeType}',
    );
    final source = input! as Map<String, Object?>;
    for (final entry in output.entries) {
      final key = entry.key;
      if (_isAbsent(source[key]) && _isAbsent(entry.value)) {
        continue;
      }
      expect(
        source.containsKey(key),
        isTrue,
        reason: '$path: toJson() invented "$key", which the payload never '
            'carried',
      );
      _expectSame(source[key], entry.value, '$path.$key');
    }
    return;
  }
  if (output is List<Object?>) {
    expect(
      input,
      isA<List<Object?>>(),
      reason: '$path: toJson() produced a list where the payload had '
          '${input.runtimeType}',
    );
    final source = input! as List<Object?>;
    expect(
      output.length,
      source.length,
      reason: '$path: toJson() produced ${output.length} elements from the '
          'payload\'s ${source.length}',
    );
    for (var i = 0; i < output.length; i++) {
      _expectSame(source[i], output[i], '$path[$i]');
    }
    return;
  }
  if (output is num && input is num) {
    expect(
      output.toDouble(),
      input.toDouble(),
      reason: '$path: decoded to $output from $input',
    );
    return;
  }
  expect(output, input, reason: '$path: decoded to $output from $input');
}

bool _isAbsent(Object? value) =>
    value == null ||
    (value is List<Object?> && value.isEmpty) ||
    (value is Map<String, Object?> && value.isEmpty);
