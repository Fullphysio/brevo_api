import 'dart:convert';

import 'package:brevo_api/brevo_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

void main() {
  group('contacts.getContacts', () {
    test('encodes typed query parameters exactly as @getbrevo/brevo 6.0.3',
        () async {
      final golden = casesOf(loadFixture('request_golden'))
          .singleWhere((c) => c['name'] == 'contacts_list_repeated_arrays');
      final expected = mapOf(golden['request']);
      http.Request? captured;
      final client = BrevoClient(
        apiKey: 'capture-api-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('{"contacts":[],"count":0}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      final page = await client.contacts.getContacts(
        limit: 10,
        offset: 0,
        modifiedSince: '2024-01-01T00:00:00.000Z',
        sort: GetContactsRequestSort.desc,
        ids: [1, 2, 3],
        listIds: [4, 5],
        filter: 'equals(FIRSTNAME,"Jo hn")',
      );

      expect(captured!.url.toString(), expected['url']);
      expect(captured!.headers['api-key'], expected['apiKey']);
      expect(page.contacts, isEmpty);
      expect(page.count, 0);
    });

    test('decodes contacts tolerantly, keeping the raw payload', () async {
      final client = BrevoClient(
        apiKey: 'k',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'contacts': [
                {
                  'email': 'john@example.com',
                  'id': 42,
                  'emailBlacklisted': false,
                  'listIds': [1, 2],
                  'attributes': {'FIRSTNAME': 'John', 'AGE': 30},
                  'createdAt': '2024-01-15T10:30:00.000Z',
                  'brandNewField': 'kept in raw',
                },
              ],
              'count': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final page = await client.contacts.getContacts(limit: 1);
      final contact = page.contacts.single;
      expect(contact.email, 'john@example.com');
      expect(contact.id, 42);
      expect(contact.emailBlacklisted, isFalse);
      expect(contact.listIds, [1, 2]);
      expect(contact.attributes, {'FIRSTNAME': 'John', 'AGE': 30});
      expect(contact.createdAt, '2024-01-15T10:30:00.000Z');
      expect(contact.createdAtDate, DateTime.utc(2024, 1, 15, 10, 30));
      expect(contact.raw['brandNewField'], 'kept in raw');
    });
  });

  group('contacts.getContactsPaged', () {
    test('walks every page by advancing the offset', () async {
      final requests = <Uri>[];
      final client = BrevoClient(
        apiKey: 'k',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final offset =
              int.parse(request.url.queryParameters['offset'] ?? '0');
          final limit = int.parse(request.url.queryParameters['limit']!);
          final ids =
              List.generate(5, (i) => i + 1).skip(offset).take(limit).toList();
          return http.Response(
            jsonEncode({
              'contacts': [
                for (final id in ids) {'id': id, 'email': 'c$id@example.com'}
              ],
              'count': 5,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final first = await client.contacts.getContactsPaged(limit: 2);
      expect(first.items.map((c) => c.id), [1, 2]);
      expect(first.count, 5);
      expect(first.hasNextPage, isTrue);

      final all = await first.autoPaging().map((c) => c.id).toList();
      expect(all, [1, 2, 3, 4, 5]);
      expect(
        requests.map((u) => u.queryParameters['offset']).toList(),
        ['0', '2', '4'],
      );
    });
  });

  group('contacts.getContactInfo', () {
    test('accepts an email or a numeric identifier', () async {
      final urls = <String>[];
      final client = BrevoClient(
        apiKey: 'k',
        httpClient: MockClient((request) async {
          urls.add(request.url.toString());
          return http.Response('{"id":1}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await client.contacts.getContactInfo(identifier: 'jo hn+x@ex.com');
      await client.contacts.getContactInfo(
          identifier: 42,
          identifierType: GetContactInfoRequestIdentifierType.emailId);
      expect(urls, [
        'https://api.brevo.com/v3/contacts/jo%20hn%2Bx%40ex.com',
        'https://api.brevo.com/v3/contacts/42?identifierType=email_id',
      ]);
    });
  });

  group('contacts.deleteContact', () {
    test('sends a bodyless DELETE', () async {
      http.Request? captured;
      final client = BrevoClient(
        apiKey: 'k',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      );
      await client.contacts.deleteContact(identifier: 'john@example.com');
      expect(captured!.method, 'DELETE');
      expect(captured!.url.path, '/v3/contacts/john%40example.com');
    });
  });
}
