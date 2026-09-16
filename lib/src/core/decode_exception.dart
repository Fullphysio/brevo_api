/// Thrown when a Brevo API response body cannot be decoded into a typed model.
///
/// Distinct from the `BrevoException` hierarchy, which represents failures
/// *returned by* Brevo or by the transport. A [BrevoDecodeException] means
/// Brevo answered successfully but the payload did not have the shape this
/// package expects of it — a body that is not JSON, or a JSON value of the
/// wrong kind where an object or list was required. Individual fields are
/// read tolerantly and decode to `null` when missing or malformed, so this
/// is only ever raised for a shape the model cannot do without.
final class BrevoDecodeException implements Exception {
  /// Creates a decode failure carrying [message] verbatim.
  BrevoDecodeException(this.message);

  /// Creates the exception for [key] missing from — or `null` in — the JSON
  /// object for [objectName].
  BrevoDecodeException.missingRequiredKey({
    required String objectName,
    required String key,
  }) : this('$objectName: required key "$key" is missing or null');

  /// Creates the exception for [key] present in the JSON object for
  /// [objectName] but holding a [value] of an unexpected type.
  BrevoDecodeException.unexpectedType({
    required String objectName,
    required String key,
    required Object? value,
  }) : this(
          '$objectName: key "$key" has an unexpected type '
          '(${value.runtimeType}): ${_describe(value)}',
        );

  /// Creates the exception for a whole payload that is not the JSON object
  /// [objectName] requires.
  BrevoDecodeException.notAnObject({
    required String objectName,
    required Object? value,
  }) : this(
          '$objectName: expected a JSON object but got '
          '${value.runtimeType}: ${_describe(value)}',
        );

  /// What went wrong, naming the object type and field involved.
  final String message;

  @override
  String toString() => 'BrevoDecodeException: $message';
}

const int _maxDescriptionLength = 200;

String _describe(Object? value) {
  final text = '$value';
  return text.length > _maxDescriptionLength
      ? '${text.substring(0, _maxDescriptionLength)}…'
      : text;
}
