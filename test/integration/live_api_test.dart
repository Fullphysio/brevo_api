@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:brevo_api/brevo_api.dart';
import 'package:test/test.dart';

/// Smoke test against the live Brevo API.
///
/// Read-only by default: it reads the account, lists a contact, the senders
/// and the transactional templates, so it is safe against any account. The
/// single write — sending one transactional email to `BREVO_TEST_RECIPIENT`
/// and deleting its log entry — runs only when `BREVO_TEST_ALLOW_WRITES` is
/// `true`. Assertions are structural — nothing depends on how many contacts
/// the account holds.
void main() {
  final env = Platform.environment;
  final apiKey = env['BREVO_TEST_API_KEY'] ?? '';
  final allowWrites = env['BREVO_TEST_ALLOW_WRITES'] == 'true';
  final recipient = env['BREVO_TEST_RECIPIENT'] ?? '';
  final templateId = int.tryParse(env['BREVO_TEST_TEMPLATE_ID'] ?? '');

  late BrevoClient brevo;

  setUpAll(() {
    if (apiKey.isEmpty) {
      fail(
        'BREVO_TEST_API_KEY is empty; export a Brevo API key to run the '
        'integration tier.',
      );
    }
    brevo = BrevoClient(apiKey: apiKey);
  });

  tearDownAll(() => brevo.close());

  test('reads the account', () async {
    final account = await brevo.account.getAccount();
    expect(account.email, isNotEmpty);
    expect(account.plan, isNotEmpty);
  });

  test('lists contacts one page at a time', () async {
    final page = await brevo.contacts.getContactsPaged(limit: 1);
    expect(page.count, isNotNull);
    expect(page.items.length, lessThanOrEqualTo(1));
    if (page.hasNextPage) {
      final next = await page.nextPage();
      expect(next.offset, 1);
    }
  });

  test('lists senders and transactional templates', () async {
    final senders = await brevo.senders.getSenders();
    expect(senders.senders, isA<List<GetSendersResponseSendersItem>>());
    final templates =
        await brevo.transactionalEmails.getSmtpTemplates(limit: 1);
    expect(templates.count, isNotNull);
  });

  test('an unknown contact is a typed 404', () async {
    await expectLater(
      brevo.contacts.getContactInfo(
          identifier:
              'nobody-${DateTime.now().microsecondsSinceEpoch}@example.invalid'),
      throwsA(isA<BrevoNotFoundException>()
          .having((e) => e.code, 'code', 'document_not_found')),
    );
  });

  test(
    'sends one transactional email and deletes its log',
    () async {
      final sent = await brevo.transactionalEmails.sendTransacEmail(
        SendTransacEmailRequest(
          templateId: templateId,
          to: [SendTransacEmailRequestToItem(email: recipient)],
          subject: templateId == null ? 'brevo_api integration test' : null,
          htmlContent:
              templateId == null ? '<p>brevo_api integration test</p>' : null,
          sender: templateId == null
              ? const SendTransacEmailRequestSender(
                  email: 'noreply@example.com', name: 'brevo_api')
              : null,
          tags: ['brevo_api-integration'],
        ),
      );
      expect(sent.messageId, isNotNull);
      await brevo.transactionalEmails
          .deleteAnSmtpTransactionalLog(identifier: sent.messageId!);
    },
    skip: allowWrites && recipient.isNotEmpty
        ? false
        : 'Set BREVO_TEST_ALLOW_WRITES=true and BREVO_TEST_RECIPIENT to send.',
  );
}
