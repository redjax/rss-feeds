#!/usr/bin/env bash
set -euo pipefail

## Load GitLab variables from the job environment
: "${GITLAB_TOKEN:?GITLAB_TOKEN is missing}"
: "${GITLAB_HOST:?GITLAB_HOST is missing}"

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../../" && pwd -P)"
cd "${REPO_ROOT}"

## Ensure .local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

git remote set-url origin "https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${CI_PROJECT_PATH}.git"

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

if [[ ! -f "${OUTPUT_DIR}/${OUTPUT_FILE}" ]]; then
  echo "[ERROR] OPML file was not created: ${OUTPUT_DIR}/${OUTPUT_FILE}" >&2
  exit 1
fi

## If the file is not in git, it's a change; otherwise compare to HEAD
if ! git ls-files "${OUTPUT_DIR}/${OUTPUT_FILE}" | grep -q "${OUTPUT_DIR}/${OUTPUT_FILE}"; then
  echo "feeds.opml is not tracked in git - treating as changed"
elif git diff --quiet "${OUTPUT_DIR}/${OUTPUT_FILE}"; then
  echo "feeds.opml did not change, exiting successfully"
  exit 0
else
  echo "feeds.opml changed - creating branch and PR"
fi

chmod +x scripts/gitlab/commit-changes.sh
GITLAB_TOKEN="$GITLAB_TOKEN" GITLAB_HOST="$GITLAB_HOST" ./scripts/gitlab/commit-changes.sh
