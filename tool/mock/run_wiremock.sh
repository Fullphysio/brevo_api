#!/usr/bin/env bash
# Starts WireMock — the stub server Brevo's own Python SDK is tested against —
# loaded with the vendored Brevo mappings, in Docker. Requests are matched on
# method, path and the listed query parameters; each answers with Brevo's
# example payload.
#
#   tool/mock/run_wiremock.sh &
#   BREVO_MOCK_HOST=127.0.0.1:8089 dart test --tags mock --run-skipped
set -euo pipefail
cd "$(dirname "$0")/../.."
exec docker run --rm --name brevo-api-wiremock \
  -p "${BREVO_MOCK_PORT:-8089}:8080" \
  -v "$PWD/tool/mock/wiremock-mappings.json:/home/wiremock/mappings/brevo.json:ro" \
  wiremock/wiremock:3.9.1 --global-response-templating --disable-banner "$@"
