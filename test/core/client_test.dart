import 'dart:convert';
import 'dart:typed_data';

import 'package:brevo_api/brevo_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

BrevoClient _client(
  MockClient httpClient, {
  Map<String, String> defaultHeaders = const {},
}) =>
    BrevoClient(
      apiKey: 'k',
      httpClient: httpClient,
      maxRetries: 0,
      defaultHeaders: defaultHeaders,
    );

void main() {
  group('the untyped escape hatch', () {
    test('requestJson sends a JSON body and decodes the reply', () async {
      http.Request? captured;
      final client = _client(MockClient((request) async {
        captured = request;
        return http.Response('{"id":7}', 200,
            headers: {'content-type': 'application/json'});
      }));

      final reply = await client.requestJson(
        method: 'POST',
        path: '/contacts',
        query: {
          'listIds': [3, 4]
        },
        body: {'email': 'ada@example.com', 'explicitNull': null},
      );

      expect(reply, {'id': 7});
      expect(captured!.method, 'POST');
      expect(captured!.url.toString(),
          'https://api.brevo.com/v3/contacts?listIds=3&listIds=4');
      expect(captured!.headers['api-key'], 'k');
      expect(
        jsonDecode(captured!.body),
        {'email': 'ada@example.com', 'explicitNull': null},
        reason: 'the escape hatch encodes the body it is handed verbatim; '
            'dropping a null field is the typed request class\'s job',
      );
    });

    test('requestVoid ignores the reply body', () async {
      final client = _client(
        MockClient((_) async => http.Response('<html>not json</html>', 204)),
      );
      await expectLater(
        client.requestVoid(method: 'DELETE', path: '/contacts/7'),
        completes,
      );
    });

    test('requestBytes returns the body untouched', () async {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x00, 0xff]);
      final client = _client(
        MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      expect(
        await client.requestBytes(method: 'GET', path: '/invoice.pdf'),
        bytes,
      );
    });

    test('requestMultipart sends fields and files as one form', () async {
      http.Request? captured;
      final client = _client(MockClient((request) async {
        captured = request;
        return http.Response('{"processId":1}', 202,
            headers: {'content-type': 'application/json'});
      }));

      final reply = await client.requestMultipart(
        path: '/companies/import',
        fields: {
          'mapping': {'name': 'company_name'},
          'dropped': null
        },
        files: {
          'file': BrevoFile(
            bytes: Uint8List.fromList(utf8.encode('name\nAcme\n')),
            filename: 'companies.csv',
            contentType: 'text/csv',
          ),
        },
      );

      expect(reply, {'processId': 1});
      expect(captured!.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      expect(captured!.body, contains('name="mapping"'));
      expect(captured!.body, contains('{"name":"company_name"}'));
      expect(captured!.body, contains('filename="companies.csv"'));
      expect(captured!.body, contains('Acme'));
      expect(captured!.body, isNot(contains('dropped')));
    });
  });

  group('defaults', () {
    test('default headers ride on every request', () async {
      http.Request? captured;
      final client = _client(
        MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        }),
        defaultHeaders: {'X-Tenant': 'fullphysio'},
      );

      await client.requestJson(method: 'GET', path: '/account');

      expect(captured!.headers['X-Tenant'], 'fullphysio');
    });

    test('per-call options override them', () async {
      http.Request? captured;
      final client = _client(
        MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        }),
        defaultHeaders: {'X-Tenant': 'fullphysio'},
      );

      await client.requestJson(
        method: 'GET',
        path: '/account',
        options: const BrevoRequestOptions(headers: {'X-Tenant': 'other'}),
      );

      expect(captured!.headers['X-Tenant'], 'other');
    });

    test('the timeout and retry budget are the documented defaults', () {
      final client = BrevoClient(apiKey: 'k');
      addTearDown(client.close);
      expect(client.timeout, const Duration(seconds: 60));
      expect(client.maxRetries, 2);
    });
  });
}
