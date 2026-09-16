import 'dart:io';

import 'package:brevo_api/brevo_api.dart';

/// Sends a templated transactional email, looks the recipient up as a
/// contact, and walks the account's contact lists — the flow a backend runs
/// behind a "send the welcome email" button.
///
/// Reads BREVO_API_KEY, BREVO_TEMPLATE_ID and BREVO_RECIPIENT from the
/// environment.
Future<void> main() async {
  final env = Platform.environment;
  final apiKey = env['BREVO_API_KEY'];
  final templateId = int.tryParse(env['BREVO_TEMPLATE_ID'] ?? '');
  final recipient = env['BREVO_RECIPIENT'];
  if (apiKey == null || templateId == null || recipient == null) {
    stderr.writeln(
        'Set BREVO_API_KEY, BREVO_TEMPLATE_ID and BREVO_RECIPIENT to run the example.');
    exitCode = 64;
    return;
  }

  final brevo = BrevoClient(apiKey: apiKey);
  try {
    final sent = await brevo.transactionalEmails.sendTransacEmail(
      SendTransacEmailRequest(
        templateId: templateId,
        to: [SendTransacEmailRequestToItem(email: recipient)],
        params: {'FIRSTNAME': 'Ada', 'LINK': 'https://example.com/welcome'},
        tags: ['welcome'],
      ),
    );
    stdout.writeln('Sent: ${sent.messageId}');

    final contact = await brevo.contacts.getContactInfo(identifier: recipient);
    stdout.writeln(
        'Contact ${contact.id} is in lists ${contact.listIds} (created ${contact.createdAtDate})');

    for (final list in (await brevo.contacts.getLists(limit: 10)).lists) {
      stdout
          .writeln('List ${list.id}: ${list.name} (${list.totalSubscribers})');
    }

    await for (final contactInList
        in (await brevo.contacts.getContactsPaged(limit: 50)).autoPaging()) {
      if (contactInList.emailBlacklisted == true) {
        stdout.writeln('Blacklisted: ${contactInList.email}');
      }
    }
  } on BrevoTooManyRequestsException catch (error) {
    stderr.writeln('Rate limited after retries: ${error.errorMessage}');
    exitCode = 1;
  } on BrevoApiException catch (error) {
    stderr.writeln('Brevo answered ${error.statusCode}: ${error.errorMessage}');
    exitCode = 1;
  } finally {
    brevo.close();
  }
}
