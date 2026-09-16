import 'dart:convert';

import 'package:brevo_api/brevo_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

void main() {
  group('transactionalEmails.sendTransacEmail', () {
    test('serialises the typed request exactly as @getbrevo/brevo 6.0.3',
        () async {
      final golden = casesOf(loadFixture('request_golden'))
          .singleWhere((c) => c['name'] == 'send_transac_email_json_body');
      final expected = mapOf(golden['request']);
      http.Request? captured;
      final client = BrevoClient(
        apiKey: 'capture-api-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            '{"messageId":"<id@relay>"}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final response = await client.transactionalEmails.sendTransacEmail(
        const SendTransacEmailRequest(
          to: [
            SendTransacEmailRequestToItem(
                email: 'john@example.com', name: 'John'),
          ],
          templateId: 5,
          params: {
            'a': 1,
            'b': null,
            'nested': {
              'list': [1, 'two', false],
            },
          },
          headers: {'X-Mailin-custom': 'x'},
          tags: ['t'],
        ),
      );

      expect(captured!.url.toString(), expected['url']);
      expect(captured!.method, 'POST');
      expect(captured!.headers['content-type'], 'application/json');
      expect(
        jsonDecode(captured!.body),
        jsonDecode(mapOf(expected['body'])['text']! as String),
        reason: 'same JSON document; upstream keeps the caller\'s key order, '
            'a typed class keeps the specification\'s',
      );
      expect(response.messageId, '<id@relay>');
      expect(response.messageIds, isEmpty);
      expect(response.raw, {'messageId': '<id@relay>'});
    });

    test('exposes the batchId of a scheduled send', () async {
      final client = BrevoClient(
        apiKey: 'k',
        httpClient: MockClient(
          (_) async => http.Response(
            '{"messageId":"<id>","batchId":"5c6cfa04"}',
            202,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final response = await client.transactionalEmails.sendTransacEmail(
        const SendTransacEmailRequest(
          templateId: 5,
          to: [SendTransacEmailRequestToItem(email: 'a@b.c')],
          scheduledAt: '2026-10-01T10:00:00.000Z',
        ),
      );
      expect(response.batchId, '5c6cfa04');
    });

    test('a Brevo error surfaces as the typed exception', () {
      final client = BrevoClient(
        apiKey: 'k',
        maxRetries: 0,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"code":"invalid_parameter","message":"Invalid email"}',
            400,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      expect(
        client.transactionalEmails.sendTransacEmail(
          const SendTransacEmailRequest(
            to: [SendTransacEmailRequestToItem(email: 'nope')],
          ),
        ),
        throwsA(
          isA<BrevoBadRequestException>()
              .having((e) => e.code, 'code', 'invalid_parameter')
              .having((e) => e.errorMessage, 'errorMessage', 'Invalid email'),
        ),
      );
    });
  });

  group('transactionalEmails.deleteSmtpLogIdentifier', () {
    test('sends a bodyless DELETE with the encoded identifier', () async {
      http.Request? captured;
      final client = BrevoClient(
        apiKey: 'k',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      );
      await client.transactionalEmails
          .deleteAnSmtpTransactionalLog(identifier: '<201798300811@relay>');
      expect(captured!.method, 'DELETE');
      expect(
        captured!.url.toString(),
        'https://api.brevo.com/v3/smtp/log/%3C201798300811%40relay%3E',
      );
      expect(captured!.body, isEmpty);
    });
  });
}
