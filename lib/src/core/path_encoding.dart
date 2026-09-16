import 'query_encoding.dart';

/// Percent-encodes [value] for use as one path segment of a Brevo API URL.
///
/// Reproduces `@getbrevo/brevo`'s `encodePathParam`: the value is stringified
/// and run through `encodeURIComponent`, so a `/`, `?`, `#`, `%`, `+`, `@` or
/// space in an identifier — an email address used as a contact identifier,
/// say — can never change the meaning of the path. An [int] identifier is
/// written in decimal.
///
/// Throws an [ArgumentError] for an empty string, `.` or `..`, none of which
/// can be a Brevo identifier and all of which would resolve to a different
/// resource than the caller intended.
String brevoPathSegment(Object value) {
  final text = value is String ? value : value.toString();
  if (text.isEmpty || text == '.' || text == '..') {
    throw ArgumentError.value(value, 'value', 'is not a valid path segment');
  }
  return brevoUriComponentEncode(text);
}
