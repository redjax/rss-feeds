#!/usr/bin/env bash
set -euo pipefail

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../.." && pwd -P)"
cd "${REPO_ROOT}"

FEEDS_FILE="${FEEDS_FILE:-feeds.yml}"
OUTPUT_DIR="${OUTPUT_DIR:-output}"
OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-10}"
REQUEST_RETRIES="${REQUEST_RETRIES:-3}"
OPML_TITLE="${OPML_TITLE:-My RSS Feeds}"

if [[ ! -f scripts/install/install-uv.sh ]]; then
  echo "[ERROR] install-uv.sh not found" >&2
  exit 1
fi

## Ensure uv is installed
./scripts/install/install-uv.sh

## Run parser via your wrapper script
./scripts/run-parser.sh \
  --input-file "${FEEDS_FILE}" \
  --output-dir "${OUTPUT_DIR}" \
  --output-file "${OUTPUT_FILE}" \
  --timeout "${REQUEST_TIMEOUT}" \
  --retries "${REQUEST_RETRIES}" \
  --opml-title "${OPML_TITLE}"

## Check if feeds.opml was created
if [[ ! -f "${OUTPUT_DIR}/${OUTPUT_FILE}" ]]; then
  echo "[ERROR] OPML file was not created: ${OUTPUT_DIR}/${OUTPUT_FILE}" >&2
  exit 1
fi

## Compare with existing file
if git diff --quiet "${OUTPUT_DIR}/${OUTPUT_FILE}"; then
  echo "feeds.opml did not change, exiting successfully"
  exit 0
fi

echo "feeds.opml changed, committing changes and creating PR"

chmod +x scripts/gitlab/commit-changes.sh
./scripts/gitlab/commit-changes.sh
