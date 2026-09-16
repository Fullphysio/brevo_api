# Conventions

This is a public package, so it does **not** follow the Fullphysio monorepo's
no-comments or 120-column rules.

- `///` dartdoc is **required** on every exported symbol. pub.dev scores it and
  IDE hovers depend on it.
- No comments on private implementation code. Name things properly instead.
- Formatting is stock `dart format` — **default width, no `--line-length`**.
  That is what `pana` and pub.dev expect with zero configuration.
  A Dart SDK from a Flutter fork or a dev channel can format differently from
  stable; CI runs official stable and is the arbiter.
- `dart analyze --fatal-infos` must be clean.

## Layout

- `lib/src/core/` — hand-written, permanent runtime: client, transport, retry
  policy, exceptions, tolerant JSON readers, offset page, query and path
  encoding, multipart file part, request options, the open-enum base.
  Generated code compiles against this and never changes it.
- `lib/src/generated/` — **generated, committed**. Never edit by hand; change
  the generator or `tool/spec/*.yaml` and regenerate. `models/`, `params/`,
  `enums/`, `unions/`, `resources/`, plus the `generated.dart` barrel.
  `test/generated/` is generated too.
- `tool/spec/` — the vendored OpenAPI spec, `resources.yaml` (operation →
  namespace and method, extracted from `@getbrevo/brevo`) and
  `union_names.yaml` (names for inline unions).
- `tool/upstream/` — the extractor that reads a `brevo-node` release and
  writes `resources.yaml`.
- `tool/ir/` — spec loading, naming rules and the resolver that classifies
  every reachable shape into a closed IR. An unmappable shape is a generation
  failure, never an `Object?` fallback.
- `tool/emit/` — the emitters. `tool/capture_fixtures/` — Node scripts that
  drive the real `@getbrevo/brevo` to produce `test/fixtures/*.json`.
  `tool/mock/` — the vendored WireMock mappings and their launcher. Nothing
  under `tool/` ships (see `.pubignore`).

## Codegen

Output is committed. There is no `build_runner` — consumers must not need a
build step.

```
dart run tool/generate.dart            # regenerate
dart run tool/generate.dart --check    # CI: fail on drift
```

Brevo publishes its spec at an unversioned URL,
`https://api.brevo.com/v3/swagger_definition_v3.yml`. Bump it with
`dart run tool/spec/update_spec.dart`, which records the SHA-256 and the
fetch date. Method and namespace names come from `@getbrevo/brevo`; bump
those with `dart run tool/upstream/extract_resources.dart --tag vX.Y.Z` where
the tag is a release of `getbrevo/brevo-node`. Do not track `main`.

A regenerate is not reviewable as a text diff. `update_spec.dart` diffs the
previous vendored spec against the new one and writes
`tool/spec/CHANGELOG_SPEC.md` (added/removed operations, schemas, enum values,
required fields); **that** is the reviewed artifact of a bump.

## Tests

Three tiers:

- **Unit and golden conformance** — the default `dart test` run. No network.
  Fixtures in `test/fixtures/*.json` were captured from the real
  `@getbrevo/brevo` (6.0.3) through its `fetch` option. When changing request
  construction, regenerate the fixtures against the same reference version
  rather than editing them by hand, and bump the version recorded in
  `THIRD_PARTY_NOTICES` and the README if you move to a newer upstream.
- **Mock server** (`--tags mock`) — WireMock, the stub server Brevo's own
  Python SDK tests against, loaded with Brevo's mappings file vendored under
  `tool/mock/`. Started by `tool/mock/run_wiremock.sh` (Docker). It matches
  path and query only — not request bodies — and validates nothing against
  the spec; request bodies are pinned by the golden tier instead. Skipped by
  tag unless `BREVO_MOCK_HOST` is set; `--run-skipped` with it empty fails
  loudly instead of dialling nowhere.
- **Integration** (`test/integration/`, `--tags integration`) — hits the live
  Brevo API with `BREVO_TEST_API_KEY`, read-only unless
  `BREVO_TEST_ALLOW_WRITES=true`. Runs from `integration.yml` on `main`,
  nightly and on dispatch — never on pull requests.

Both tagged tiers are skipped in a plain `dart test`. GitHub Actions
substitutes an empty string for an undefined variable, so every emptiness
check is `isEmpty`, not `== null`. Assertions are structural: never assert on
how many contacts an account holds, or the suite rots.

## Conformance with @getbrevo/brevo

This package reproduces `@getbrevo/brevo` 6.0.3 behaviour deliberately,
including quirks. Before "fixing" something that looks wrong, check the
reference — if the JavaScript does it, we do it, and the reason belongs in a
test name, not a code comment.

- Query arrays use the `repeat` format: `ids=1&ids=2`. Keys and values are
  percent-encoded like `encodeURIComponent`, so `!*'()` stay literal and `,`
  `:` `[` `]` are escaped. A `null` value is dropped, not sent empty.
- Path parameters go through `encodeURIComponent` too (`@` and `+` in an
  email identifier are escaped). `.`, `..` and the empty string are rejected.
- Request bodies are `JSON.stringify` output: a Dart `null` field is omitted
  (the generated `toJson` skips it) and there is no way to send an explicit
  JSON `null` except through a raw `Map` such as template `params`.
- `Accept` is always `*/*`.
- Retries: 408, 429 and 5xx only, twice by default. A connection failure or a
  timeout is **not** retried. Delay precedence: `Retry-After` in seconds
  (read like `parseInt`, must be positive, capped at 60 s), `Retry-After` as
  a date in the future (capped), `X-RateLimit-Reset` as unix seconds in the
  future (capped, +0–20 % jitter), then `1 s × 2^attempt` capped at 60 s with
  ±10 % jitter. There are **no idempotency keys** — Brevo defines none, so a
  retried POST is exactly as eager as upstream.
- The error message is `Status code: <n>` followed by `Body: <body>` — a JSON
  body pretty-printed at two spaces, a text body quoted, no `Body` line for
  an empty body under a JSON content type. Upstream prefixes its JavaScript
  class name on one more line; a Dart port cannot, so the golden test strips
  it. The body is decoded as JSON only when the response declares a JSON
  content type; otherwise the raw text is kept, an empty string included.
- Deliberate divergence: the exception subtype is chosen by status code for
  **every** operation. Upstream only raises a typed error for the statuses
  the spec lists on that operation and a generic `BrevoError` for the rest.
- Deliberate divergence: `partnerKey` is a constructor option sent as the
  `partner-key` header. The spec defines it; upstream has no option for it.
- Multipart parts: a `Map` or `List` field is sent JSON-encoded (the
  `mapping` of an import); scalars are stringified; a `null` field is
  omitted. Part order is not significant and is not reproduced.

## Releasing

1. Bump `version:` in `pubspec.yaml` and `lib/src/core/version.dart` (a test
   keeps them in step) and add a `CHANGELOG.md` entry.
2. Merge to `main` and let CI go green.
3. Tag and push:

   ```
   git tag v1.2.3 && git push origin v1.2.3
   ```

Publishing is permanent: a version can be retracted within 7 days but never
deleted, and the number is never reusable. The `description:` in
`pubspec.yaml` must stay at or under 180 characters or pana drops the score.
