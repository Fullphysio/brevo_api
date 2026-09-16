// Captures test/fixtures/request_golden.json: the exact URL, method, headers
// and body @getbrevo/brevo produces for representative calls — repeated
// array query parameters, percent-encoding of query values and path
// segments, JSON body serialisation (null kept, undefined dropped) and the
// multipart shape of the three upload endpoints. Each case records the
// `input` the Dart transport must be driven with to reproduce the request.

'use strict';

const { loadBrevo, recordingFetch, clientWith, writeFixture } = require('./common');

const Brevo = loadBrevo();

async function capture(name, input, invoke, responseBody, options) {
  const { fetch, calls } = recordingFetch([{ status: 200, body: responseBody === undefined ? {} : responseBody }]);
  const client = clientWith(Brevo, fetch, options);
  let error = null;
  try {
    await invoke(client);
  } catch (err) {
    error = { className: err.constructor.name, message: err.message };
  }
  const call = calls[0] || null;
  return {
    name,
    input: {
      method: input.method,
      path: input.path,
      pathParams: input.pathParams === undefined ? null : input.pathParams,
      query: input.query === undefined ? null : input.query,
      body: input.body === undefined ? null : input.body,
    },
    error,
    request: call && {
      url: call.url,
      method: call.method,
      contentType: call.headers['content-type'] || null,
      accept: call.headers['accept'] || null,
      apiKey: call.headers['api-key'] || null,
      body: call.body,
    },
  };
}

async function main() {
  const cases = [];

  const contactsQuery = {
    limit: 10,
    offset: 0,
    modifiedSince: '2024-01-01T00:00:00.000Z',
    sort: 'desc',
    ids: [1, 2, 3],
    listIds: [4, 5],
    filter: 'equals(FIRSTNAME,"Jo hn")',
  };
  cases.push(
    await capture(
      'contacts_list_repeated_arrays',
      { method: 'GET', path: '/contacts', query: contactsQuery },
      (c) => c.contacts.getContacts(contactsQuery),
      { contacts: [], count: 0 },
    ),
  );

  const reservedQuery = { limit: 1, filter: "a b&c=d!*'()[x]100%é/ü+~" };
  cases.push(
    await capture(
      'query_reserved_characters',
      { method: 'GET', path: '/contacts', query: reservedQuery },
      (c) => c.contacts.getContacts(reservedQuery),
      { contacts: [], count: 0 },
    ),
  );

  const flagsQuery = { limit: 2, offset: 0, sort: 'asc', excludeHtmlContent: true, excludePdfAttachment: false };
  cases.push(
    await capture(
      'campaigns_boolean_query',
      { method: 'GET', path: '/emailCampaigns', query: flagsQuery },
      (c) => c.emailCampaigns.getEmailCampaigns(flagsQuery),
      { campaigns: [], count: 0 },
    ),
  );

  cases.push(
    await capture(
      'path_segment_reserved_characters',
      { method: 'GET', path: '/contacts/{identifier}', pathParams: { identifier: 'jo hn+x@ex.com/ü?#%' }, query: { identifierType: 'email_id' } },
      (c) => c.contacts.getContactInfo({ identifier: 'jo hn+x@ex.com/ü?#%', identifierType: 'email_id' }),
      { email: 'x' },
    ),
  );

  cases.push(
    await capture(
      'path_segment_integer',
      { method: 'GET', path: '/contacts/lists/{listId}/contacts', pathParams: { listId: 12 }, query: { limit: 5 } },
      (c) => c.contacts.getContactsFromList({ listId: 12, limit: 5 }),
      { contacts: [], count: 0 },
    ),
  );

  const email = {
    to: [{ email: 'john@example.com', name: 'John' }],
    templateId: 5,
    params: { a: 1, b: null, c: undefined, nested: { list: [1, 'two', false] } },
    headers: { 'X-Mailin-custom': 'x' },
    tags: ['t'],
    subject: undefined,
  };
  cases.push(
    await capture(
      'send_transac_email_json_body',
      { method: 'POST', path: '/smtp/email', body: email },
      (c) => c.transactionalEmails.sendTransacEmail(email),
      { messageId: '<id@relay>' },
    ),
  );

  cases.push(
    await capture(
      'delete_without_body',
      { method: 'DELETE', path: '/contacts/{identifier}', pathParams: { identifier: '42' } },
      (c) => c.contacts.deleteContact({ identifier: '42' }),
      null,
    ),
  );

  const upload = { file: new File(['hello'], 'notes.txt', { type: 'text/plain' }), dealId: 'd1', companyId: 'c1', contactId: 7 };
  cases.push(
    await capture(
      'crm_files_multipart',
      {
        method: 'POST',
        path: '/crm/files',
        body: { file: { filename: 'notes.txt', contentType: 'text/plain', text: 'hello' }, dealId: 'd1', companyId: 'c1', contactId: 7 },
      },
      (c) => c.files.uploadAFile(upload),
      { id: 'f1' },
    ),
  );

  const companiesImport = { file: new File(['name,email\nAcme,a@b.c'], 'companies.csv', { type: 'text/csv' }), mapping: { name: 'name' } };
  cases.push(
    await capture(
      'companies_import_multipart',
      {
        method: 'POST',
        path: '/companies/import',
        body: { file: { filename: 'companies.csv', contentType: 'text/csv', text: 'name,email\nAcme,a@b.c' }, mapping: { name: 'name' } },
      },
      (c) => c.companies.importCompaniesCreationAndUpdation(companiesImport),
      { processId: 1 },
    ),
  );

  writeFixture('request_golden', {
    seam: 'the `fetch` client option with maxRetries: 0; apiKey "capture-api-key"',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
