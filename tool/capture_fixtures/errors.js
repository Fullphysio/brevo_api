// Captures test/fixtures/error_golden.json: the exception class, message and
// decoded body @getbrevo/brevo raises for each error status and body shape.

'use strict';

const { loadBrevo, recordingFetch, clientWith, writeFixture, orNull } = require('./common');

const Brevo = loadBrevo();

async function capture(name, statusCode, body, headers) {
  const { fetch } = recordingFetch([{ status: statusCode, body, headers }]);
  const client = clientWith(Brevo, fetch);
  let outcome;
  try {
    await client.contacts.getContactInfo({ identifier: 'john@example.com' });
    outcome = { threw: false };
  } catch (err) {
    outcome = {
      threw: true,
      className: err.constructor.name,
      message: err.message,
      statusCode: orNull(err.statusCode),
      body: orNull(err.body),
    };
  }
  return { name, input: { statusCode, body: body === undefined ? null : body, headers: headers || {} }, expected: outcome };
}

async function main() {
  const brevoError = (code, message) => ({ code, message });
  const cases = [];
  for (const [status, label] of [
    [400, 'bad_request'],
    [401, 'unauthorized'],
    [402, 'payment_required'],
    [403, 'forbidden'],
    [404, 'not_found'],
    [405, 'method_not_allowed'],
    [409, 'conflict'],
    [412, 'precondition_failed'],
    [415, 'unsupported_media_type'],
    [417, 'expectation_failed'],
    [422, 'unprocessable_entity'],
    [424, 'failed_dependency'],
    [425, 'too_early'],
    [429, 'too_many_requests'],
    [500, 'internal_server'],
  ]) {
    cases.push(await capture(label + '_' + status, status, brevoError(label, 'Message for ' + status)));
  }
  cases.push(await capture('bad_gateway_502_json', 502, brevoError('bad_gateway', 'Upstream down')));
  cases.push(await capture('teapot_418_unmapped', 418, brevoError('teapot', 'short and stout')));
  cases.push(await capture('html_body_502', 502, '<html><body>Bad Gateway</body></html>', { 'content-type': 'text/html' }));
  cases.push(await capture('empty_body_500', 500, ''));
  cases.push(await capture('empty_body_404_json_content_type', 404, '', { 'content-type': 'application/json' }));
  cases.push(await capture('message_only_400', 400, { message: 'Only a message' }));
  cases.push(await capture('json_array_body_400', 400, ['not', 'an', 'object']));
  cases.push(await capture('contact_error_model_425', 425, { code: 'too_early', message: 'Retry later', metadata: { retryAfter: 30 } }));
  cases.push(await capture('json_with_charset_400', 400, JSON.stringify(brevoError('bad_request', 'charset')), { 'content-type': 'application/json; charset=utf-8' }));
  cases.push(await capture('plain_text_no_content_type_400', 400, 'plain text', {}));

  writeFixture('error_golden', {
    seam: 'contacts.getContactInfo through the `fetch` client option with maxRetries: 0',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
