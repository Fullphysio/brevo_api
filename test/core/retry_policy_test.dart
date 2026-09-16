import 'dart:math';

import 'package:brevo_api/src/core/retry_policy.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.Response _response(int statusCode) => http.Response('', statusCode);

void main() {
  group('brevoShouldRetry', () {
    test('never retries once the retry budget is exhausted', () {
      expect(
        brevoShouldRetry(attempt: 2, maxRetries: 2, response: _response(500)),
        isFalse,
      );
    });

    for (final status in [408, 429, 500, 502, 503, 504]) {
      test('retries a $status', () {
        expect(
          brevoShouldRetry(
              attempt: 0, maxRetries: 2, response: _response(status)),
          isTrue,
        );
      });
    }

    for (final status in [400, 401, 404, 409, 422, 425]) {
      test('does not retry a $status', () {
        expect(
          brevoShouldRetry(
              attempt: 0, maxRetries: 2, response: _response(status)),
          isFalse,
        );
      });
    }

    test('does not retry when there was no response, as upstream', () {
      expect(brevoShouldRetry(attempt: 0, maxRetries: 2), isFalse);
    });
  });

  group('brevoRetryDelay', () {
    final now = DateTime.utc(2026, 9, 16, 12);

    Duration delay(Map<String, String> headers,
            {int attempt = 0, int seed = 1}) =>
        brevoRetryDelay(
          attempt: attempt,
          headers: headers,
          random: Random(seed),
          now: now,
        );

    test('Retry-After in whole seconds is honoured exactly', () {
      expect(delay({'retry-after': '3'}), const Duration(seconds: 3));
    });

    test('Retry-After reads a leading integer like parseInt', () {
      expect(delay({'retry-after': '1.9'}), const Duration(seconds: 1));
      expect(delay({'retry-after': ' 5 seconds'}), const Duration(seconds: 5));
    });

    test('Retry-After is capped at 60 seconds', () {
      expect(delay({'retry-after': '600'}), brevoMaxRetryDelay);
    });

    test('Retry-After as an HTTP-date in the future is honoured', () {
      expect(
        delay({'retry-after': 'Wed, 16 Sep 2026 12:00:30 GMT'}),
        const Duration(seconds: 30),
      );
    });

    test('Retry-After as an HTTP-date is capped at 60 seconds', () {
      expect(delay({'retry-after': 'Wed, 16 Sep 2026 12:05:00 GMT'}),
          brevoMaxRetryDelay);
    });

    test('an HTTP-date in the past falls through to the backoff', () {
      final result = delay({'retry-after': 'Wed, 21 Oct 2015 07:28:00 GMT'});
      expect(result, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      expect(result, lessThanOrEqualTo(const Duration(milliseconds: 1100)));
    });

    test('a zero or unparsable Retry-After falls through to the backoff', () {
      for (final value in ['0', 'soon', '-3']) {
        final result = delay({'retry-after': value});
        expect(result, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
        expect(result, lessThanOrEqualTo(const Duration(milliseconds: 1100)));
      }
    });

    test('X-RateLimit-Reset in the future is honoured with positive jitter',
        () {
      final reset =
          now.add(const Duration(seconds: 10)).millisecondsSinceEpoch ~/ 1000;
      final results = List<Duration>.generate(
        50,
        (seed) => delay({'x-ratelimit-reset': '$reset'}, seed: seed),
      );
      for (final result in results) {
        expect(result, greaterThanOrEqualTo(const Duration(seconds: 10)));
        expect(result, lessThanOrEqualTo(const Duration(seconds: 12)));
      }
      expect(results.toSet().length, greaterThan(1));
    });

    test('X-RateLimit-Reset is capped before jitter is applied', () {
      final reset =
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final result = delay({'x-ratelimit-reset': '$reset'});
      expect(result, greaterThanOrEqualTo(brevoMaxRetryDelay));
      expect(result, lessThanOrEqualTo(brevoMaxRetryDelay * 1.2));
    });

    test('Retry-After wins over X-RateLimit-Reset', () {
      final reset =
          now.add(const Duration(seconds: 10)).millisecondsSinceEpoch ~/ 1000;
      expect(
        delay({'retry-after': '2', 'x-ratelimit-reset': '$reset'}),
        const Duration(seconds: 2),
      );
    });

    test('X-RateLimit-Reset in the past falls through to the backoff', () {
      final result = delay({'x-ratelimit-reset': '1000000000'});
      expect(result, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      expect(result, lessThanOrEqualTo(const Duration(milliseconds: 1100)));
    });

    test('backs off from 1 s, doubling per attempt, with ±10 % jitter', () {
      for (final (attempt, seconds) in [(0, 1), (1, 2), (2, 4), (5, 32)]) {
        final results = List<Duration>.generate(
          50,
          (seed) => delay(const {}, attempt: attempt, seed: seed),
        );
        final nominal = Duration(seconds: seconds);
        for (final result in results) {
          expect(result, greaterThanOrEqualTo(nominal * 0.9),
              reason: 'attempt $attempt');
          expect(result, lessThanOrEqualTo(nominal * 1.1),
              reason: 'attempt $attempt');
        }
        expect(results.toSet().length, greaterThan(1));
      }
    });

    test('the backoff is capped at 60 seconds', () {
      final result = delay(const {}, attempt: 10);
      expect(result, greaterThanOrEqualTo(brevoMaxRetryDelay * 0.9));
      expect(result, lessThanOrEqualTo(brevoMaxRetryDelay * 1.1));
    });
  });
}
