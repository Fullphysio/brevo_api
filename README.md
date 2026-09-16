# brevo_api

[![CI](https://github.com/Fullphysio/brevo_api/actions/workflows/ci.yml/badge.svg)](https://github.com/Fullphysio/brevo_api/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/Fullphysio/brevo_api/badge.svg?branch=main)](https://coveralls.io/github/Fullphysio/brevo_api?branch=main)

A pure Dart client for the [Brevo](https://www.brevo.com) API (formerly
Sendinblue). Runs on Dart servers, CLIs and Flutter apps — there is no Flutter
dependency, and no code generation step for you.

```dart
final brevo = BrevoClient(apiKey: apiKey);

final sent = await brevo.transactionalEmails.sendTransacEmail(
  SendTransacEmailRequest(
    templateId: 42,
    to: [SendTransacEmailRequestToItem(email: 'ada@example.com')],
    params: {'FIRSTNAME': 'Ada'},
  ),
);
print(sent.messageId);

final contact = await brevo.contacts.getContactInfo(identifier: 'ada@example.com');
print(contact.listIds);
```

## Why this exists

No Dart package covers the Brevo REST API. This package is a port of the
official Node.js client, `@getbrevo/brevo`: the runtime — transport, retries,
error mapping, query and path encoding, body serialisation — is a hand port
verified against fixtures captured from the real client, and every model and
resource method is generated from Brevo's own OpenAPI specification by a
generator that lives in this repository. Following a Brevo release is a
command, not a rewrite.

## Usage

Every one of the 34 Brevo resources hangs off the client under the name the
Node.js client uses, so Brevo's own documentation applies:
`brevo.contacts`, `brevo.transactionalEmails`, `brevo.transactionalSms`,
`brevo.emailCampaigns`, `brevo.senders`, `brevo.webhooks`, `brevo.companies`,
`brevo.deals`, `brevo.ecommerce`, `brevo.event`, `brevo.masterAccount`, …

Path and query parameters are named arguments; a request body is a typed
positional object. Every method takes an optional `options` argument for a
per-call timeout, retry budget or extra headers.

Resources hang off the client through an extension, so they are reachable
wherever `package:brevo_api/brevo_api.dart` is imported. Re-exporting
`BrevoClient` from your own façade means re-exporting this library with it,
or `client.contacts` will not resolve at the call site.

```dart
await brevo.contacts.updateContact(
  UpdateContactRequest(attributes: {'FIRSTNAME': 'Ada', 'PLAN': 'pro'}),
  identifier: 'ada@example.com',
);

final campaigns = await brevo.emailCampaigns.getEmailCampaigns(
  status: GetEmailCampaignsRequestStatus.sent,
  limit: 20,
  options: const BrevoRequestOptions(timeout: Duration(seconds: 10)),
);
```

### Pagination

Brevo paginates with `limit` / `offset` and reports a `count`. Every list
that does has a `…Paged` twin returning a `BrevoOffsetPage`:

```dart
final page = await brevo.contacts.getContactsPaged(limit: 500, listIds: [7]);
await for (final contact in page.autoPaging()) {
  print(contact.email);
}
```

### Files

The three upload endpoints take a `BrevoFile`:

```dart
await brevo.companies.importCompaniesCreationAndUpdation(
  PostCompaniesImportRequest(
    file: BrevoFile(bytes: csvBytes, filename: 'companies.csv', contentType: 'text/csv'),
    mapping: {'name': 'company_name'},
  ),
);
```

### Escape hatch

`brevo.requestJson`, `requestVoid`, `requestBytes` and `requestMultipart`
reach any endpoint this package does not model yet, with the same
authentication, retries and error mapping.

## Models

Response models decode **tolerantly**: a field Brevo omits, renames or retypes
reads as `null` (or an empty list), never throws, and the whole payload stays
available as `.raw`. Timestamps are kept as the strings Brevo sends, with a
`…Date` getter that parses them. Enums are open: `CampaignStatus.fromWire('new')`
returns a value with `isKnown == false` instead of failing, so a Brevo release
never breaks decoding. Request bodies honour the specification's `required`
fields at the constructor.

## Errors

Every failure is a `BrevoException`, a sealed hierarchy:

| Exception | When |
|---|---|
| `BrevoBadRequestException` … `BrevoTooManyRequestsException`, `BrevoInternalServerException` | a 400, 401, 402, 403, 404, 405, 409, 412, 415, 417, 422, 424, 425, 429 or 5xx response, with Brevo's `code` and `errorMessage` |
| `BrevoUnexpectedStatusException` | any other non-2xx status |
| `BrevoConnectionException`, `BrevoTimeoutException` | the request never produced a response |

`BrevoDecodeException` (outside the hierarchy) means Brevo answered
successfully but the payload was not JSON, or not the object or list the
operation returns.

## Fidelity to @getbrevo/brevo

This client reproduces `@getbrevo/brevo` 6.0.3's observable behaviour,
including details that are easy to get subtly wrong:

- Retries on 408, 429 and 5xx — twice by default — honouring `Retry-After`
  (seconds or a date), then `X-RateLimit-Reset`, then a 1 s-doubling backoff
  capped at 60 s with ±10 % jitter. A connection failure or timeout is not
  retried, as upstream. Brevo defines no idempotency keys, so a retried `POST`
  is exactly as eager as upstream.
- Query arrays repeat the key, `ids=1&ids=2`; keys and values are encoded like
  `encodeURIComponent`. A `null` field of a request body is omitted, exactly
  as `JSON.stringify` drops `undefined`.
- Error messages follow the `Status code: 400` / `Body: {…}` layout upstream
  prints, with the body decoded as JSON only under a JSON content type.

Conformance is enforced by golden tests whose fixtures — request URLs and
bodies, error messages, and which statuses are retried and how often — were
captured from the real `@getbrevo/brevo` rather than written by hand. The
length of each backoff is the exception: the captures pin the retry
*decisions*, while the 60 s cap and the jitter are covered by unit tests
written against upstream's implementation. A mock-server tier then calls all
291 operations against WireMock loaded with Brevo's own mappings, checking
each one's request against the server's journal.

## Scope

**Covered.** Every operation of the Brevo v3 specification — 291 operations
across 34 resources, with typed parameters, request bodies, response models and
open enums generated from it — plus offset pagination helpers and multipart
uploads.

**Not covered.** Inbound webhook payload models (Brevo does not sign
webhooks; parse deliveries with `jsonDecode`) and the OAuth / custom
authentication hooks of the Node.js client.

## Deliberate divergences from @getbrevo/brevo

- Nothing is read from environment variables; the API key is always explicit.
- `Future`s instead of `HttpResponsePromise`; the raw JSON is one
  `requestJson` call away.
- The exception subtype is chosen by status code for every operation, where
  upstream types only the statuses the specification lists per operation.
- `partnerKey` is a constructor option sent as the `partner-key` header, which
  the specification defines and the Node.js client lacks.
- Undiscriminated `oneOf` request bodies (adding contacts to a list by
  `emails`, `ids` or `extIds`, say) are one class with every alternative's
  fields optional, rather than a union type.
- No `X-Fern-*` headers; the `User-Agent` is `brevo_api/<version> (Dart)`.
