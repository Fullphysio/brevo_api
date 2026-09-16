import 'dart:convert';

/// Serialises [query] into a URL query string the way `@getbrevo/brevo` does.
///
/// Reproduces Fern's query-string builder with `arrayFormat: "repeat"`:
///
/// - a `null` value is dropped entirely (omit the key to send nothing;
///   there is no way to send an empty value, matching upstream);
/// - a `List` value repeats the bare key once per non-null element —
///   `ids=1&ids=2` — and an empty list contributes nothing;
/// - a nested `Map` becomes `key[sub]=value`, an empty map nothing;
/// - `bool`, `num` and `String` are written as their JS `String()` form, so
///   a whole-valued `double` is written without a fractional part;
/// - a [DateTime] is written as an ISO-8601 UTC instant with millisecond
///   precision, like `Date.prototype.toISOString`.
///
/// Both keys and values are percent-encoded like `encodeURIComponent`: the
/// RFC 3986 unreserved set plus `!*'()` stay literal, everything else —
/// including `[` and `]` — is escaped from its UTF-8 bytes. Pairs keep the
/// insertion order of [query].
String brevoQueryEncode(Map<String, Object?> query) {
  final pairs = <String>[];
  for (final entry in query.entries) {
    _write(entry.key, entry.value, pairs);
  }
  return pairs.join('&');
}

void _write(String prefix, Object? value, List<String> pairs) {
  if (value == null) {
    return;
  }
  if (value is List<Object?>) {
    for (final element in value) {
      if (element == null) {
        continue;
      }
      if (element is Map<String, Object?>) {
        _write(prefix, element, pairs);
      } else {
        pairs.add(
          '${brevoUriComponentEncode(prefix)}='
          '${brevoUriComponentEncode(_scalarToString(element))}',
        );
      }
    }
    return;
  }
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _write('$prefix[${entry.key}]', entry.value, pairs);
    }
    return;
  }
  pairs.add(
    '${brevoUriComponentEncode(prefix)}='
    '${brevoUriComponentEncode(_scalarToString(value))}',
  );
}

String _scalarToString(Object value) => switch (value) {
      final DateTime date => _isoString(date.toUtc()),
      final bool flag => '$flag',
      final int number => '$number',
      final double number => _doubleToString(number),
      final String text => text,
      _ => value.toString(),
    };

String _doubleToString(double number) {
  if (number.isFinite && number == number.roundToDouble()) {
    return number.toInt().toString();
  }
  return number.toString();
}

String _isoString(DateTime utc) {
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
      'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
      '.${pad(utc.millisecond, 3)}Z';
}

/// Percent-encodes [text] exactly as JavaScript's `encodeURIComponent`:
/// `A–Z a–z 0–9 - _ . ! ~ * ' ( )` stay literal, every other byte of the
/// UTF-8 encoding becomes `%XX` with upper-case hex digits.
String brevoUriComponentEncode(String text) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(text)) {
    if (_isLiteral(byte)) {
      buffer.writeCharCode(byte);
    } else {
      buffer
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

bool _isLiteral(int byte) =>
    (byte >= 0x41 && byte <= 0x5a) ||
    (byte >= 0x61 && byte <= 0x7a) ||
    (byte >= 0x30 && byte <= 0x39) ||
    _literalPunctuation.contains(byte);

const Set<int> _literalPunctuation = {
  0x2d, // -
  0x5f, // _
  0x2e, // .
  0x21, // !
  0x7e, // ~
  0x2a, // *
  0x27, // '
  0x28, // (
  0x29, // )
};
