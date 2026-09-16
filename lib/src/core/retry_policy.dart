import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// The longest delay a retry ever waits, whatever the response asked for.
const Duration brevoMaxRetryDelay = Duration(seconds: 60);

/// Decides whether a Brevo request attempt should be retried.
///
/// Reproduces `@getbrevo/brevo` 6.0.3: an attempt is retried while
/// [attempt] is below [maxRetries] and the response status is 408, 429 or
/// any 5xx. A request that produced no [response] at all — a connection
/// failure or a timeout — is *not* retried, because upstream does not retry
/// it either. Brevo defines no idempotency-key mechanism, so a retried
/// `POST` is exactly as eager here as upstream. That is inherited, not
/// introduced.
bool brevoShouldRetry({
  required int attempt,
  required int maxRetries,
  http.Response? response,
}) {
  if (attempt >= maxRetries || response == null) {
    return false;
  }
  final status = response.statusCode;
  return status == 408 || status == 429 || status >= 500;
}

/// Computes how long to wait before the retry numbered [attempt] (zero-based)
/// of a request that received [headers], reproducing `@getbrevo/brevo`'s
/// precedence:
///
/// 1. `Retry-After` as a positive whole number of seconds (a leading integer
///    prefix, as `parseInt` reads it), capped at [brevoMaxRetryDelay];
/// 2. `Retry-After` as an HTTP-date or ISO-8601 instant later than [now],
///    capped likewise;
/// 3. `X-RateLimit-Reset` as a unix-seconds instant later than [now], capped
///    and lengthened by a random jitter of up to 20 %;
/// 4. otherwise `min(1 s × 2^attempt, 60 s)` with a symmetric random jitter
///    of ±10 %.
///
/// A header value that is unparsable, zero, or in the past falls through to
/// the next rule. [random] and [now] are injection seams for deterministic
/// tests.
Duration brevoRetryDelay({
  required int attempt,
  Map<String, String> headers = const {},
  Random? random,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final retryAfter = headers['retry-after'];
  if (retryAfter != null) {
    final seconds = _parseInt(retryAfter);
    if (seconds != null && seconds > 0) {
      return _capped(Duration(seconds: seconds));
    }
    final date = _parseDate(retryAfter);
    if (date != null) {
      final delay = date.difference(current);
      if (delay > Duration.zero) {
        return _capped(delay);
      }
    }
  }
  final reset = headers['x-ratelimit-reset'];
  if (reset != null) {
    final resetSeconds = _parseInt(reset);
    if (resetSeconds != null) {
      final delay = Duration(seconds: resetSeconds) -
          Duration(milliseconds: current.millisecondsSinceEpoch);
      if (delay > Duration.zero) {
        return _jitter(_capped(delay), (random ?? Random()).nextDouble() * 0.2);
      }
    }
  }
  final backoff = _capped(Duration(seconds: 1) * pow(2, attempt).toInt());
  return _jitter(backoff, ((random ?? Random()).nextDouble() - 0.5) * 0.2);
}

Duration _capped(Duration delay) =>
    delay > brevoMaxRetryDelay ? brevoMaxRetryDelay : delay;

Duration _jitter(Duration delay, double factor) => Duration(
      microseconds: (delay.inMicroseconds * (1 + factor)).round(),
    );

final RegExp _leadingInteger = RegExp(r'^\s*[+-]?\d+');

int? _parseInt(String text) {
  final match = _leadingInteger.firstMatch(text);
  return match == null ? null : int.tryParse(match.group(0)!.trim());
}

DateTime? _parseDate(String text) {
  final trimmed = text.trim();
  final iso = DateTime.tryParse(trimmed);
  if (iso != null) {
    return iso;
  }
  try {
    return parseHttpDate(trimmed);
  } on FormatException {
    return null;
  }
}
