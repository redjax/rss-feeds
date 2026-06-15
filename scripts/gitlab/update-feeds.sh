#!/usr/bin/env bash
set -euo pipefail

## Load GitLab variables from the job environment
: "${GITLAB_TOKEN:?GITLAB_TOKEN is missing}"
: "${GITLAB_HOST:?GITLAB_HOST is missing}"

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../../" && pwd -P)"
cd "${REPO_ROOT}"

FEEDS_FILE="${FEEDS_FILE:-.raw/feeds.yml}"
OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-10}"
REQUEST_RETRIES="${REQUEST_RETRIES:-3}"
OPML_TITLE="${OPML_TITLE:-My RSS Feeds}"

## Ensure uv is installed
./scripts/install/install-uv.sh

## Run parser via your wrapper script
./scripts/run-parser.sh \
  --input-file "${FEEDS_FILE}" \
  --output-file "${OUTPUT_FILE}" \
  --timeout "${REQUEST_TIMEOUT}" \
  --retries "${REQUEST_RETRIES}" \
  --opml-title "${OPML_TITLE}"

if [[ ! -f "${OUTPUT_FILE}" ]]; then
  echo "[ERROR] Missing output: ${OUTPUT_FILE}" >&2
  exit 1
fi

chmod +x scripts/gitlab/commit-changes.sh
GITLAB_TOKEN="$GITLAB_TOKEN" GITLAB_HOST="$GITLAB_HOST" ./scripts/gitlab/commit-changes.sh
