import 'dart:convert';

/// Base class for every failure this package raises while talking to Brevo.
///
/// Sealed, so a `switch` over a caught [BrevoException] is exhaustive. Two
/// families exist: an error status returned by the API ([BrevoApiException]
/// and its subtypes) and a request that never produced a response
/// ([BrevoConnectionException], [BrevoTimeoutException]). A successful
/// response whose body does not have the expected shape is deliberately
/// outside this hierarchy — see `BrevoDecodeException`.
sealed class BrevoException implements Exception {
  /// Creates an exception carrying [message].
  const BrevoException(this.message);

  /// What went wrong, in one line — or several for an API error, which
  /// reproduces the `Status code: …` / `Body: …` layout of `@getbrevo/brevo`.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A non-2xx response from the Brevo API, raised once retries are exhausted
/// or the status was not retryable in the first place.
///
/// The concrete subtype is chosen by HTTP status code alone. Brevo's error
/// body, `{"code": "…", "message": "…"}`, is surfaced through [code] and
/// [errorMessage] but never participates in choosing the subtype.
sealed class BrevoApiException extends BrevoException {
  /// Creates an API exception from a decoded error response.
  const BrevoApiException({
    required String message,
    required this.statusCode,
    required this.headers,
    this.code,
    this.errorMessage,
    this.body,
  }) : super(message);

  /// The HTTP status code of the response.
  final int statusCode;

  /// The response headers, lower-cased keys.
  final Map<String, String> headers;

  /// Brevo's `code` label, such as `invalid_parameter` or `document_not_found`,
  /// when the body carried one.
  final String? code;

  /// Brevo's human-readable `message`, when the body carried one.
  final String? errorMessage;

  /// The decoded JSON body when the response declared a JSON content type,
  /// the raw text otherwise, or `null` for an empty JSON response.
  final Object? body;

  /// The `x-request-id` header Brevo attaches to responses, when present.
  String? get requestId => headers['x-request-id'];
}

/// HTTP 400.
final class BrevoBadRequestException extends BrevoApiException {
  /// Creates the exception for a 400 response.
  const BrevoBadRequestException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 401: the API key was rejected.
final class BrevoUnauthorizedException extends BrevoApiException {
  /// Creates the exception for a 401 response.
  const BrevoUnauthorizedException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 402: not enough credits, or a plan upgrade is needed.
final class BrevoPaymentRequiredException extends BrevoApiException {
  /// Creates the exception for a 402 response.
  const BrevoPaymentRequiredException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 403: the key lacks permission for this operation.
final class BrevoForbiddenException extends BrevoApiException {
  /// Creates the exception for a 403 response.
  const BrevoForbiddenException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 404.
final class BrevoNotFoundException extends BrevoApiException {
  /// Creates the exception for a 404 response.
  const BrevoNotFoundException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 405.
final class BrevoMethodNotAllowedException extends BrevoApiException {
  /// Creates the exception for a 405 response.
  const BrevoMethodNotAllowedException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 409.
final class BrevoConflictException extends BrevoApiException {
  /// Creates the exception for a 409 response.
  const BrevoConflictException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 412.
final class BrevoPreconditionFailedException extends BrevoApiException {
  /// Creates the exception for a 412 response.
  const BrevoPreconditionFailedException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 415.
final class BrevoUnsupportedMediaTypeException extends BrevoApiException {
  /// Creates the exception for a 415 response.
  const BrevoUnsupportedMediaTypeException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 417.
final class BrevoExpectationFailedException extends BrevoApiException {
  /// Creates the exception for a 417 response.
  const BrevoExpectationFailedException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 422.
final class BrevoUnprocessableEntityException extends BrevoApiException {
  /// Creates the exception for a 422 response.
  const BrevoUnprocessableEntityException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 424.
final class BrevoFailedDependencyException extends BrevoApiException {
  /// Creates the exception for a 424 response.
  const BrevoFailedDependencyException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 425: the contact is still being processed; retry later.
final class BrevoTooEarlyException extends BrevoApiException {
  /// Creates the exception for a 425 response.
  const BrevoTooEarlyException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// HTTP 429. Retried by default, honouring `Retry-After`, before it is
/// thrown.
final class BrevoTooManyRequestsException extends BrevoApiException {
  /// Creates the exception for a 429 response.
  const BrevoTooManyRequestsException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// Any 5xx. Retried by default before it is thrown.
final class BrevoInternalServerException extends BrevoApiException {
  /// Creates the exception for a 5xx response.
  const BrevoInternalServerException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// A non-2xx status none of the other subtypes claims, such as 408 or 418.
final class BrevoUnexpectedStatusException extends BrevoApiException {
  /// Creates the exception for an unclassified error status.
  const BrevoUnexpectedStatusException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.code,
    super.errorMessage,
    super.body,
  });
}

/// The request never produced a response: DNS failure, connection reset, TLS
/// error. Not retried, as upstream does not retry it either.
final class BrevoConnectionException extends BrevoException {
  /// Creates a connection failure, optionally wrapping the transport-level
  /// [cause].
  const BrevoConnectionException({
    String message = 'Connection error.',
    this.cause,
  }) : super(message);

  /// The underlying error thrown by the HTTP client, when there was one.
  final Object? cause;
}

/// The request exceeded the client's timeout. Not retried.
final class BrevoTimeoutException extends BrevoException {
  /// Creates a timeout failure for the [method] and [path] that timed out,
  /// in the wording of `@getbrevo/brevo`.
  BrevoTimeoutException({required String method, required String path})
      : super('Timeout exceeded when calling $method $path.');
}

/// Builds the [BrevoApiException] subtype for a non-2xx response, reproducing
/// how `@getbrevo/brevo` decodes the body and formats the message.
///
/// The body is decoded as JSON when the response's `Content-Type` is a JSON
/// media type (`application/json`, `text/json`, `application/*+json`), in
/// which case an empty body decodes to `null`; any other content type — or
/// none — keeps the raw text, an empty string included. The message is
/// `Status code: <status>`, followed by `Body: <body>` when there is one,
/// with a JSON body pretty-printed at two spaces and a text body quoted.
///
/// [body] is the raw response text, never pre-parsed.
BrevoApiException brevoApiExceptionFromResponse({
  required int statusCode,
  required Map<String, String> headers,
  required String body,
}) {
  final decoded = brevoDecodeErrorBody(
    contentType: headers['content-type'],
    body: body,
  );
  final message =
      brevoFormatErrorMessage(statusCode: statusCode, body: decoded);
  final code = decoded is Map<String, Object?> && decoded['code'] is String
      ? decoded['code'] as String
      : null;
  final errorMessage =
      decoded is Map<String, Object?> && decoded['message'] is String
          ? decoded['message'] as String
          : null;

  return switch (statusCode) {
    400 => BrevoBadRequestException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    401 => BrevoUnauthorizedException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    402 => BrevoPaymentRequiredException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    403 => BrevoForbiddenException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    404 => BrevoNotFoundException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    405 => BrevoMethodNotAllowedException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    409 => BrevoConflictException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    412 => BrevoPreconditionFailedException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    415 => BrevoUnsupportedMediaTypeException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    417 => BrevoExpectationFailedException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    422 => BrevoUnprocessableEntityException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    424 => BrevoFailedDependencyException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    425 => BrevoTooEarlyException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    429 => BrevoTooManyRequestsException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    >= 500 => BrevoInternalServerException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
    _ => BrevoUnexpectedStatusException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        code: code,
        errorMessage: errorMessage,
        body: decoded,
      ),
  };
}

/// Decodes an error response [body] the way `@getbrevo/brevo` does: as JSON
/// when [contentType] names a JSON media type (an empty body then yields
/// `null`; unparsable JSON falls back to the text), as the raw text
/// otherwise.
Object? brevoDecodeErrorBody({
  required String? contentType,
  required String body,
}) {
  if (!_isJsonContentType(contentType)) {
    return body;
  }
  if (body.isEmpty) {
    return null;
  }
  try {
    return jsonDecode(body);
  } on FormatException {
    return body;
  }
}

/// Formats the message of a [BrevoApiException]: `Status code: <status>`,
/// then `Body: <body>` on a new line when [body] is not `null` — a JSON value
/// pretty-printed with two-space indentation, a string quoted as JSON.
String brevoFormatErrorMessage({required int statusCode, Object? body}) {
  final lines = <String>['Status code: $statusCode'];
  if (body != null) {
    lines.add('Body: ${_prettyJsonEncoder.convert(body)}');
  }
  return lines.join('\n');
}

const JsonEncoder _prettyJsonEncoder = JsonEncoder.withIndent('  ');

bool _isJsonContentType(String? contentType) {
  if (contentType == null || contentType.isEmpty) {
    return false;
  }
  var mediaType = contentType.toLowerCase();
  final semicolon = mediaType.indexOf(';');
  if (semicolon != -1) {
    mediaType = mediaType.substring(0, semicolon).trim();
  }
  return switch (mediaType) {
    'application/hal+json' ||
    'application/json' ||
    'application/ld+json' ||
    'application/problem+json' ||
    'application/vnd.api+json' ||
    'text/json' =>
      true,
    _ =>
      mediaType.startsWith('application/vnd.') && mediaType.endsWith('+json'),
  };
}
