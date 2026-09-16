import 'query_encoding.dart';

/// Percent-encodes [value] for use as one path segment of a Brevo API URL.
///
/// Reproduces `@getbrevo/brevo`'s `encodePathParam`: the value is stringified
/// and run through `encodeURIComponent`, so a `/`, `?`, `#`, `%`, `+`, `@` or
/// space in an identifier — an email address used as a contact identifier,
/// say — can never change the meaning of the path. An [int] identifier is
/// written in decimal.
///
/// A handful of Brevo paths accept either form of identifier — a contact by
/// numeric id or by email address — and are typed `Object` for that reason.
/// Anything that is neither a [String] nor a number is therefore rejected
/// here rather than stringified into a request that would quietly address
/// the wrong resource.
///
/// Throws an [ArgumentError] for an empty string, `.` or `..`, none of which
/// can be a Brevo identifier and all of which would resolve to a different
/// resource than the caller intended.
String brevoPathSegment(Object value) {
  if (value is! String && value is! num) {
    throw ArgumentError.value(
      value,
      'value',
      'a path parameter must be a String or a number',
    );
  }
  final text = value is String ? value : '$value';
  if (text.isEmpty || text == '.' || text == '..') {
    throw ArgumentError.value(value, 'value', 'is not a valid path segment');
  }
  return brevoUriComponentEncode(text);
}
