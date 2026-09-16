// Captures test/fixtures/retry_golden.json: how many attempts @getbrevo/brevo
// makes for each status / header combination with maxRetries: 2, what it
// finally throws or returns, and how a connection failure or a timeout
// surfaces. Retry-After headers are set to one second so the capture runs
// quickly; the recorded `elapsedMs` shows they were honoured.

'use strict';

const { loadBrevo, recordingFetch, clientWith, writeFixture } = require('./common');

const Brevo = loadBrevo();

async function capture(name, responses, options) {
  const { fetch, calls } = recordingFetch(responses);
  const client = clientWith(Brevo, fetch, Object.assign({ maxRetries: 2 }, options));
  const started = Date.now();
  let outcome;
  try {
    const result = await client.contacts.getContactInfo({ identifier: 'john@example.com' });
    outcome = { threw: false, resultEmail: result && result.email ? result.email : null };
  } catch (err) {
    outcome = { threw: true, className: err.constructor.name, message: err.message };
  }
  return {
    name,
    responses: responses.map((r) => ({ status: r.status || null, headers: r.headers || {}, throws: !!r.throw, hangs: !!r.hang })),
    attempts: calls.length,
    elapsedMs: Date.now() - started,
    expected: outcome,
  };
}

async function main() {
  const ok = { status: 200, body: { email: 'john@example.com' } };
  const fast = { 'retry-after': '1' };
  const failure = (status, headers) => ({ status, body: { code: 'c', message: 'm' }, headers });

  const cases = [];
  cases.push(await capture('500_then_success', [failure(500, fast), ok]));
  cases.push(await capture('500_exhausts_two_retries', [failure(500, fast), failure(500, fast), failure(500, fast)]));
  cases.push(await capture('408_retried', [failure(408, fast), ok]));
  cases.push(await capture('429_retried', [failure(429, fast), ok]));
  cases.push(await capture('503_retried', [failure(503, fast), ok]));
  cases.push(await capture('409_not_retried', [failure(409, fast), ok]));
  cases.push(await capture('400_not_retried', [failure(400, fast), ok]));
  cases.push(await capture('404_not_retried', [failure(404, fast), ok]));
  cases.push(await capture('connection_error_not_retried', [{ throw: 'fetch failed' }, ok]));
  cases.push(await capture('retry_after_http_date_in_past', [failure(503, { 'retry-after': 'Wed, 21 Oct 2015 07:28:00 GMT' }), ok]));
  cases.push(await capture('rate_limit_reset_in_past', [failure(429, { 'x-ratelimit-reset': '1000000000' }), ok]));
  cases.push(await capture('max_retries_zero', [failure(500, fast), ok], { maxRetries: 0 }));
  cases.push(await capture('timeout', [{ hang: true }], { timeoutInSeconds: 0.2 }));

  writeFixture('retry_golden', {
    seam: 'contacts.getContactInfo through the `fetch` client option; maxRetries: 2 unless stated',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
