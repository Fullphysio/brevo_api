import 'package:meta/meta.dart';

/// Per-call overrides of the client's defaults, accepted by every generated
/// resource method as its last, optional argument.
///
/// Mirrors the `requestOptions` argument of `@getbrevo/brevo`: a longer
/// [timeout] for a bulk import, `maxRetries: 0` for a call that must not be
/// repeated, or extra [headers] for one request.
@immutable
final class BrevoRequestOptions {
  /// Creates a set of overrides; every field left `null` keeps the client's
  /// default.
  const BrevoRequestOptions({
    this.timeout,
    this.maxRetries,
    this.headers = const {},
  });

  /// The deadline for receiving response headers on each attempt of this
  /// request.
  final Duration? timeout;

  /// How many times a failed attempt of this request is retried.
  final int? maxRetries;

  /// Headers added to this request; they override the client's defaults and
  /// the headers this package sets when the names collide.
  final Map<String, String> headers;
}
