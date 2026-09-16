// Shared helpers for the fixture-capture scripts. Each script drives the REAL
// `@getbrevo/brevo` client through its `fetch` option with canned responses
// and records what it produced, so the Dart tests compare against upstream
// behaviour rather than against what we believe it to be.
//
//   mkdir -p /tmp/brevo-ref && cd /tmp/brevo-ref && npm install @getbrevo/brevo@6.0.3
//   node /path/to/brevo_api/tool/capture_fixtures/<script>.js
//
// `require('@getbrevo/brevo')` is resolved against the current working
// directory.

'use strict';

const fs = require('fs');
const path = require('path');

const BREVO_NODE_VERSION = '6.0.3';

function loadBrevo() {
  let resolved;
  try {
    resolved = require.resolve('@getbrevo/brevo', { paths: [process.cwd()] });
  } catch (e) {
    throw new Error(
      'Could not resolve "@getbrevo/brevo" from ' +
        process.cwd() +
        '. Run this script from a directory with @getbrevo/brevo ' +
        BREVO_NODE_VERSION +
        ' installed, e.g.:\n' +
        '  mkdir -p /tmp/brevo-ref && cd /tmp/brevo-ref\n' +
        '  npm install @getbrevo/brevo@' +
        BREVO_NODE_VERSION,
    );
  }
  const installed = installedVersion(resolved);
  if (installed !== BREVO_NODE_VERSION) {
    throw new Error('Installed @getbrevo/brevo is ' + installed + ', expected ' + BREVO_NODE_VERSION);
  }
  return require(resolved);
}

function installedVersion(resolvedEntry) {
  let dir = path.dirname(resolvedEntry);
  for (let i = 0; i < 8; i++) {
    const candidate = path.join(dir, 'package.json');
    if (fs.existsSync(candidate)) {
      const pkg = JSON.parse(fs.readFileSync(candidate, 'utf8'));
      if (pkg.name === '@getbrevo/brevo') return pkg.version;
    }
    dir = path.dirname(dir);
  }
  throw new Error('Could not locate @getbrevo/brevo package.json from ' + resolvedEntry);
}

function headersToObject(headers) {
  const out = {};
  for (const [key, value] of new Headers(headers).entries()) out[key] = value;
  return out;
}

async function describeBody(body) {
  if (body == null) return null;
  if (typeof body === 'string') return { kind: 'text', text: body };
  if (typeof FormData !== 'undefined' && body instanceof FormData) {
    const parts = [];
    for (const [name, value] of body.entries()) {
      if (typeof value === 'string') {
        parts.push({ name, text: value });
      } else {
        parts.push({
          name,
          filename: value.name === undefined ? null : value.name,
          contentType: value.type || null,
          text: await value.text(),
        });
      }
    }
    return { kind: 'form-data', parts };
  }
  return { kind: 'other', constructor: body.constructor ? body.constructor.name : null };
}

// Builds a `fetch` that answers each call with the next canned response and
// records every request it saw. `responses` entries are
// `{ status, body, headers }`; an entry with `throw: 'message'` makes fetch
// reject, simulating a connection error, and `hang: true` never resolves.
function recordingFetch(responses) {
  const calls = [];
  let index = 0;
  const fetch = async (url, init) => {
    const spec = responses[Math.min(index, responses.length - 1)];
    index += 1;
    calls.push({
      url: String(url),
      method: init && init.method ? String(init.method) : 'GET',
      headers: init && init.headers ? headersToObject(init.headers) : {},
      body: await describeBody(init && init.body),
    });
    if (spec.throw) throw new TypeError(spec.throw);
    if (spec.hang) {
      return new Promise((_, reject) => {
        if (init && init.signal) {
          init.signal.addEventListener('abort', () => reject(init.signal.reason));
        }
      });
    }
    const isJson = spec.body !== undefined && spec.body !== null && typeof spec.body !== 'string';
    const body = spec.body === undefined || spec.body === null ? null : isJson ? JSON.stringify(spec.body) : spec.body;
    return new Response(body, {
      status: spec.status,
      headers: Object.assign(isJson ? { 'content-type': 'application/json' } : {}, spec.headers || {}),
    });
  };
  return { fetch, calls };
}

function clientWith(Brevo, fetch, options) {
  return new Brevo.BrevoClient(Object.assign({ apiKey: 'capture-api-key', fetch, maxRetries: 0 }, options));
}

function writeFixture(name, fixture) {
  const outPath = path.join(__dirname, '..', '..', 'test', 'fixtures', name + '.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(
    outPath,
    JSON.stringify(Object.assign({ capturedFrom: { package: '@getbrevo/brevo', version: BREVO_NODE_VERSION } }, fixture), null, 2) + '\n',
  );
  console.log('Wrote ' + outPath);
}

function orNull(value) {
  return value === undefined ? null : value;
}

module.exports = { BREVO_NODE_VERSION, loadBrevo, recordingFetch, clientWith, writeFixture, headersToObject, orNull };
