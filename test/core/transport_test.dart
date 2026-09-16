import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:brevo_api/src/core/decode_exception.dart';
import 'package:brevo_api/src/core/exceptions.dart';
import 'package:brevo_api/src/core/multipart.dart';
import 'package:brevo_api/src/core/path_encoding.dart';
import 'package:brevo_api/src/core/request_options.dart';
import 'package:brevo_api/src/core/transport.dart';
import 'package:brevo_api/src/core/version.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

BrevoTransport _transport(
  http.Client client, {
  int maxRetries = 0,
  Duration timeout = const Duration(seconds: 5),
  Uri? baseUrl,
  String? partnerKey,
  Map<String, String> defaultHeaders = const {},
  List<Duration>? delays,
}) =>
    BrevoTransport(
      apiKey: 'capture-api-key',
      partnerKey: partnerKey,
      httpClient: client,
      timeout: timeout,
      maxRetries: maxRetries,
      baseUrl: baseUrl,
      defaultHeaders: defaultHeaders,
      random: Random(1),
      sleep: (delay) async => delays?.add(delay),
    );

final class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);

  @override
  void close() {
    closed = true;
  }
}

final class _LateClient extends http.BaseClient {
  _LateClient(this._response);
  final Future<http.StreamedResponse> _response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _response;
}

/// Answers with response headers straight away and a body that never ends.
final class _StallingBodyClient extends http.BaseClient {
  _StallingBodyClient(this._body);
  final Stream<List<int>> _body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(_body, 200);
}

String _substitutePath(Map<String, Object?> input) {
  var path = input['path']! as String;
  final params = input['pathParams'] as Map<String, Object?>?;
  if (params != null) {
    for (final entry in params.entries) {
      path = path.replaceAll(
        '{${entry.key}}',
        brevoPathSegment(entry.value!),
      );
    }
  }
  return path;
}

List<Map<String, Object?>> _parseMultipart(http.Request request) {
  final contentType = request.headers['content-type']!;
  final boundary = RegExp(r'boundary=(.+)$').firstMatch(contentType)!.group(1)!;
  final body = utf8.decode(request.bodyBytes);
  final parts = <Map<String, Object?>>[];
  for (final chunk in body.split('--$boundary')) {
    final trimmed = chunk.trim();
    if (trimmed.isEmpty || trimmed == '--') {
      continue;
    }
    final separator = trimmed.indexOf('\r\n\r\n');
    final headerBlock = trimmed.substring(0, separator);
    final content = trimmed.substring(separator + 4);
    final name = RegExp(r'name="([^"]*)"').firstMatch(headerBlock)!.group(1);
    final filename =
        RegExp(r'filename="([^"]*)"').firstMatch(headerBlock)?.group(1);
    final type = RegExp(r'content-type:\s*(\S+)', caseSensitive: false)
        .firstMatch(headerBlock)
        ?.group(1);
    parts.add({
      'name': name,
      if (filename != null) 'filename': filename,
      if (filename != null) 'contentType': type,
      'text': content,
    });
  }
  return parts;
}

void main() {
  group('requests match @getbrevo/brevo 6.0.3 byte for byte', () {
    for (final testCase in casesOf(loadFixture('request_golden'))) {
      final input = mapOf(testCase['input']);
      final expected = mapOf(testCase['request']);
      test(testCase['name']! as String, () async {
        http.Request? captured;
        final transport = _transport(MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        }));
        final body = input['body'];
        final expectedBody = expected['body'] as Map<String, Object?>?;

        if (expectedBody != null && expectedBody['kind'] == 'form-data') {
          final fields = <String, Object?>{};
          final files = <String, BrevoFile>{};
          for (final entry in mapOf(body).entries) {
            final value = entry.value;
            if (value is Map<String, Object?> &&
                value.containsKey('filename')) {
              files[entry.key] = BrevoFile(
                bytes:
                    Uint8List.fromList(utf8.encode(value['text']! as String)),
                filename: value['filename']! as String,
                contentType: value['contentType'] as String?,
              );
            } else {
              fields[entry.key] = value;
            }
          }
          await transport.requestMultipart(
            path: _substitutePath(input),
            fields: fields,
            files: files,
          );
          final request = captured!;
          expect(request.url.toString(), expected['url']);
          expect(request.method, expected['method']);
          expect(request.headers['content-type'],
              startsWith('multipart/form-data; boundary='));
          expect(
            _parseMultipart(request),
            unorderedEquals(
              (expectedBody['parts']! as List<Object?>)
                  .cast<Map<String, Object?>>(),
            ),
          );
        } else {
          await transport.send(
            method: input['method']! as String,
            path: _substitutePath(input),
            query: input['query'] as Map<String, Object?>?,
            body: body,
          );
          final request = captured!;
          expect(request.url.toString(), expected['url']);
          expect(request.method, expected['method']);
          expect(request.headers['content-type'], expected['contentType']);
          expect(
            request.body.isEmpty ? null : request.body,
            expectedBody == null ? null : expectedBody['text'],
          );
        }
        expect(captured!.headers['accept'], expected['accept']);
        expect(captured!.headers['api-key'], expected['apiKey']);
      });
    }
  });

  group('retry behaviour matches @getbrevo/brevo 6.0.3', () {
    for (final testCase in casesOf(loadFixture('retry_golden'))) {
      final name = testCase['name']! as String;
      final responses = (testCase['responses']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final expected = mapOf(testCase['expected']);
      test(name, () async {
        var calls = 0;
        final delays = <Duration>[];
        final client = MockClient((request) async {
          final spec = responses[min(calls, responses.length - 1)];
          calls++;
          if (spec['throws'] == true) {
            throw http.ClientException('fetch failed', request.url);
          }
          if (spec['hangs'] == true) {
            return Completer<http.Response>().future;
          }
          final status = spec['status']! as int;
          final body = status == 200
              ? '{"email":"john@example.com"}'
              : '{"code":"c","message":"m"}';
          return http.Response(
            body,
            status,
            headers: {
              'content-type': 'application/json',
              ...mapOf(spec['headers']).cast<String, String>(),
            },
          );
        });
        final transport = _transport(
          client,
          maxRetries: name == 'max_retries_zero' ? 0 : 2,
          timeout: name == 'timeout'
              ? const Duration(milliseconds: 20)
              : const Duration(seconds: 5),
          delays: delays,
        );

        Future<Object?> run() => transport.requestJson(
              method: 'GET',
              path: '/contacts/john%40example.com',
            );

        if (expected['threw'] == true) {
          final Matcher type = switch (name) {
            'connection_error_not_retried' => isA<BrevoConnectionException>(),
            'timeout' => isA<BrevoTimeoutException>(),
            _ => isA<BrevoApiException>().having(
                (e) => e.message,
                'message',
                upstreamMessageWithoutClassName(expected),
              ),
          };
          await expectLater(run(), throwsA(type));
        } else {
          final result = mapOf(await run());
          expect(result['email'], expected['resultEmail']);
        }
        expect(calls, testCase['attempts']);
        expect(delays.length, calls - 1);

        switch (name) {
          case 'retry_after_http_date_in_past':
          case 'rate_limit_reset_in_past':
            expect(delays.single,
                greaterThanOrEqualTo(const Duration(milliseconds: 900)));
            expect(delays.single,
                lessThanOrEqualTo(const Duration(milliseconds: 1100)));
          default:
            for (final delay in delays) {
              expect(delay, const Duration(seconds: 1));
            }
        }
      });
    }
  });

  group('headers', () {
    test('sends the api-key, User-Agent, Accept and partner-key headers',
        () async {
      http.Request? captured;
      final transport = _transport(
        MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        }),
        partnerKey: 'partner',
        defaultHeaders: const {'X-Custom': 'a'},
      );
      await transport.requestJson(
        method: 'GET',
        path: '/account',
        options: const BrevoRequestOptions(headers: {'X-Per-Call': 'b'}),
      );
      final headers = captured!.headers;
      expect(headers['api-key'], 'capture-api-key');
      expect(headers['partner-key'], 'partner');
      expect(headers['user-agent'], 'brevo_api/$brevoApiVersion (Dart)');
      expect(headers['accept'], '*/*');
      expect(headers['x-custom'], 'a');
      expect(headers['x-per-call'], 'b');
    });

    test('per-call headers override the defaults', () async {
      http.Request? captured;
      final transport = _transport(
        MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        }),
        defaultHeaders: const {'X-Custom': 'a'},
      );
      await transport.requestJson(
        method: 'GET',
        path: '/account',
        options: const BrevoRequestOptions(headers: {'X-Custom': 'b'}),
      );
      expect(captured!.headers['x-custom'], 'b');
    });
  });

  group('request options', () {
    test('maxRetries can be overridden per call', () async {
      var calls = 0;
      final transport = _transport(
        MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
        maxRetries: 2,
      );
      await expectLater(
        transport.requestJson(
          method: 'GET',
          path: '/account',
          options: const BrevoRequestOptions(maxRetries: 0),
        ),
        throwsA(isA<BrevoInternalServerException>()),
      );
      expect(calls, 1);
    });

    test('timeout can be overridden per call', () {
      final transport = _transport(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(seconds: 30),
      );
      expect(
        transport.requestJson(
          method: 'GET',
          path: '/account',
          options:
              const BrevoRequestOptions(timeout: Duration(milliseconds: 20)),
        ),
        throwsA(isA<BrevoTimeoutException>()),
      );
    });
  });

  group('timeouts', () {
    test('an attempt exceeding the timeout throws BrevoTimeoutException', () {
      final client = MockClient((_) => Completer<http.Response>().future);
      final transport =
          _transport(client, timeout: const Duration(milliseconds: 20));
      expect(
        transport.requestJson(method: 'GET', path: '/account'),
        throwsA(
          isA<BrevoTimeoutException>().having(
            (e) => e.message,
            'message',
            'Timeout exceeded when calling GET /account.',
          ),
        ),
      );
    });

    test('a response arriving after the timeout is drained, not leaked',
        () async {
      final late = Completer<http.StreamedResponse>();
      final drained = Completer<void>();
      final body = StreamController<List<int>>(
        onListen: () => drained.complete(),
      );
      final client = _LateClient(late.future);
      final transport =
          _transport(client, timeout: const Duration(milliseconds: 20));

      await expectLater(
        transport.requestJson(method: 'GET', path: '/account'),
        throwsA(isA<BrevoTimeoutException>()),
      );
      late.complete(http.StreamedResponse(body.stream, 200));
      await body.close();

      await expectLater(drained.future, completes);
    });

    test('a body that stalls after the headers arrived still times out',
        () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final transport = _transport(
        _StallingBodyClient(body.stream),
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        transport.requestJson(method: 'GET', path: '/account'),
        throwsA(isA<BrevoTimeoutException>()),
      );
    });
  });

  group('response decoding', () {
    test('an empty 2xx body decodes to null', () async {
      final transport =
          _transport(MockClient((_) async => http.Response('', 204)));
      expect(
        await transport.requestJson(method: 'DELETE', path: '/contacts/1'),
        isNull,
      );
    });

    test('a non-JSON 2xx body is a decode failure, not silently null', () {
      final transport = _transport(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      expect(
        transport.requestJson(method: 'GET', path: '/account'),
        throwsA(isA<BrevoDecodeException>()),
      );
    });

    test('a body that is not valid UTF-8 is a decode failure too', () {
      final transport = _transport(
        MockClient(
          (_) async => http.Response.bytes(const [0xff, 0xfe, 0xff], 200),
        ),
      );
      expect(
        transport.requestJson(method: 'GET', path: '/account'),
        throwsA(isA<BrevoDecodeException>()),
      );
    });

    test('requestVoid ignores whatever body came back', () async {
      final transport = _transport(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      await expectLater(
        transport.requestVoid(method: 'DELETE', path: '/contacts/1'),
        completes,
      );
    });

    test('requestBytes returns the raw body', () async {
      final transport = _transport(
        MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      );
      expect(
          await transport.requestBytes(method: 'GET', path: '/x'), [1, 2, 3]);
    });

    test('a 2xx status other than 200 is a success', () async {
      final transport = _transport(
        MockClient((_) async => http.Response('{"processId":1}', 202)),
      );
      expect(
        await transport.requestJson(method: 'POST', path: '/x'),
        {'processId': 1},
      );
    });
  });

  group('errors', () {
    test('a non-retryable status throws the matching exception', () {
      final transport = _transport(
        MockClient(
          (_) async => http.Response(
            '{"code":"document_not_found","message":"Contact not found"}',
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      expect(
        transport.requestJson(method: 'GET', path: '/contacts/1'),
        throwsA(
          isA<BrevoNotFoundException>()
              .having((e) => e.code, 'code', 'document_not_found')
              .having(
                  (e) => e.errorMessage, 'errorMessage', 'Contact not found'),
        ),
      );
    });

    test('a connection failure wraps the cause', () {
      final transport = _transport(
        MockClient(
            (request) async => throw http.ClientException('boom', request.url)),
      );
      expect(
        transport.requestJson(method: 'GET', path: '/account'),
        throwsA(
          isA<BrevoConnectionException>()
              .having((e) => e.cause, 'cause', isA<http.ClientException>()),
        ),
      );
    });
  });

  group('base URL', () {
    test('defaults to https://api.brevo.com/v3', () async {
      String? url;
      final transport = _transport(MockClient((request) async {
        url = request.url.toString();
        return http.Response('{}', 200);
      }));
      await transport.requestJson(method: 'GET', path: '/account');
      expect(url, 'https://api.brevo.com/v3/account');
    });

    test('an explicit baseUrl replaces the origin and prefix', () async {
      String? url;
      final transport = _transport(
        MockClient((request) async {
          url = request.url.toString();
          return http.Response('{}', 200);
        }),
        baseUrl: Uri.parse('http://127.0.0.1:8080/'),
      );
      await transport.requestJson(method: 'GET', path: '/account');
      expect(url, 'http://127.0.0.1:8080/account');
    });
  });

  group('multipart', () {
    test('null fields are omitted and scalars stringified', () async {
      http.Request? captured;
      final transport = _transport(MockClient((request) async {
        captured = request;
        return http.Response('{"id":"f1"}', 200);
      }));
      final result = await transport.requestMultipart(
        path: '/crm/files',
        fields: {'contactId': 7, 'dealId': null, 'flag': true},
        files: {
          'file': BrevoFile(
            bytes: Uint8List.fromList(utf8.encode('hello')),
            filename: 'notes.txt',
          ),
        },
      );
      expect(result, {'id': 'f1'});
      final parts = _parseMultipart(captured!);
      expect(parts, [
        {'name': 'contactId', 'text': '7'},
        {'name': 'flag', 'text': 'true'},
        {
          'name': 'file',
          'filename': 'notes.txt',
          'contentType': 'application/octet-stream',
          'text': 'hello',
        },
      ]);
    });

    test('a multipart request is rebuilt for each retry', () async {
      var calls = 0;
      final transport = _transport(
        MockClient((_) async {
          calls++;
          return http.Response('', calls == 1 ? 503 : 200);
        }),
        maxRetries: 1,
        delays: [],
      );
      await transport.requestMultipart(
        path: '/crm/files',
        fields: const {},
        files: {
          'file': BrevoFile(bytes: Uint8List(0), filename: 'empty.bin'),
        },
      );
      expect(calls, 2);
    });
  });

  group('close', () {
    test('does not close a caller-supplied client', () {
      final client = _TrackingClient();
      _transport(client).close();
      expect(client.closed, isFalse);
    });

    test('closes the client it created', () {
      final transport = BrevoTransport(
        apiKey: 'k',
        timeout: const Duration(seconds: 1),
        maxRetries: 0,
      );
      expect(transport.close, returnsNormally);
    });
  });
}
