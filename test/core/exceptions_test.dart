import 'dart:convert';

import 'package:brevo_api/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

final Map<String, Matcher> _upstreamClass = {
  'BadRequestError': isA<BrevoBadRequestException>(),
  'NotFoundError': isA<BrevoNotFoundException>(),
  'BrevoError': isA<BrevoApiException>(),
};

final Map<int, Matcher> _statusClass = {
  400: isA<BrevoBadRequestException>(),
  401: isA<BrevoUnauthorizedException>(),
  402: isA<BrevoPaymentRequiredException>(),
  403: isA<BrevoForbiddenException>(),
  404: isA<BrevoNotFoundException>(),
  405: isA<BrevoMethodNotAllowedException>(),
  409: isA<BrevoConflictException>(),
  412: isA<BrevoPreconditionFailedException>(),
  415: isA<BrevoUnsupportedMediaTypeException>(),
  417: isA<BrevoExpectationFailedException>(),
  422: isA<BrevoUnprocessableEntityException>(),
  424: isA<BrevoFailedDependencyException>(),
  425: isA<BrevoTooEarlyException>(),
  429: isA<BrevoTooManyRequestsException>(),
  500: isA<BrevoInternalServerException>(),
  502: isA<BrevoInternalServerException>(),
  418: isA<BrevoUnexpectedStatusException>(),
};

String _bodyText(Object? body) => body is String ? body : jsonEncode(body);

Map<String, String> _headersOf(Map<String, Object?> input, Object? body) {
  final headers = mapOf(input['headers']).cast<String, String>();
  if (body is String || headers.containsKey('content-type')) {
    return headers;
  }
  return {'content-type': 'application/json', ...headers};
}

void main() {
  group('golden fixtures captured from @getbrevo/brevo 6.0.3', () {
    for (final testCase in casesOf(loadFixture('error_golden'))) {
      final input = mapOf(testCase['input']);
      final expected = mapOf(testCase['expected']);
      final statusCode = input['statusCode']! as int;
      test(testCase['name']! as String, () {
        final exception = brevoApiExceptionFromResponse(
          statusCode: statusCode,
          headers: _headersOf(input, input['body']),
          body: _bodyText(input['body']),
        );
        expect(exception, _upstreamClass[expected['className']]!);
        expect(exception, _statusClass[statusCode]!);
        expect(exception.message, upstreamMessageWithoutClassName(expected));
        expect(exception.statusCode, expected['statusCode']);
        expect(exception.body, expected['body']);
      });
    }
  });

  group('Brevo error body', () {
    test('surfaces code and message', () {
      final exception = brevoApiExceptionFromResponse(
        statusCode: 400,
        headers: const {'content-type': 'application/json'},
        body: '{"code":"invalid_parameter","message":"email is invalid"}',
      );
      expect(exception.code, 'invalid_parameter');
      expect(exception.errorMessage, 'email is invalid');
    });

    test('leaves code and message null when the body lacks them', () {
      final exception = brevoApiExceptionFromResponse(
        statusCode: 400,
        headers: const {'content-type': 'application/json'},
        body: '{"code":42,"message":["a"]}',
      );
      expect(exception.code, isNull);
      expect(exception.errorMessage, isNull);
      expect(exception.body, {
        'code': 42,
        'message': ['a'],
      });
    });

    test('unparsable JSON under a JSON content type keeps the text', () {
      final exception = brevoApiExceptionFromResponse(
        statusCode: 500,
        headers: const {'content-type': 'application/json'},
        body: '<html>',
      );
      expect(exception.body, '<html>');
      expect(exception.message, 'Status code: 500\nBody: "<html>"');
    });

    test('vendor JSON media types decode as JSON', () {
      final exception = brevoApiExceptionFromResponse(
        statusCode: 400,
        headers: const {'content-type': 'application/vnd.brevo+json'},
        body: '{"message":"m"}',
      );
      expect(exception.body, {'message': 'm'});
    });

    test('requestId reads the x-request-id header', () {
      final exception = brevoApiExceptionFromResponse(
        statusCode: 500,
        headers: const {'x-request-id': 'req_1'},
        body: '',
      );
      expect(exception.requestId, 'req_1');
    });
  });

  group('sealed hierarchy', () {
    test('toString names the type and the message', () {
      const exception = BrevoConnectionException(message: 'boom');
      expect(exception.toString(), 'BrevoConnectionException: boom');
    });

    test('a timeout names the call, as upstream', () {
      final exception =
          BrevoTimeoutException(method: 'POST', path: '/smtp/email');
      expect(
        exception.message,
        'Timeout exceeded when calling POST /smtp/email.',
      );
    });

    test('every status maps to its own subtype', () {
      for (final entry in _statusClass.entries) {
        expect(
          brevoApiExceptionFromResponse(
            statusCode: entry.key,
            headers: const {},
            body: '',
          ),
          entry.value,
          reason: 'status ${entry.key}',
        );
      }
    });
  });
}
