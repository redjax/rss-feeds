#!/usr/bin/env bash
set -euo pipefail

## Load GitLab variables from the job environment
: "${GITLAB_TOKEN:?GITLAB_TOKEN is missing}"
: "${GITLAB_HOST:?GITLAB_HOST is missing}"

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../../" && pwd -P)"
cd "${REPO_ROOT}"

FEEDS_INPUT="${FEEDS_INPUT:-.raw/}"
OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-10}"
REQUEST_RETRIES="${REQUEST_RETRIES:-3}"
OPML_TITLE="${OPML_TITLE:-My RSS Feeds}"

## Ensure .local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

## Ensure uv is installed
if ! ./scripts/install/install-uv.sh; then
  echo "[ERROR] uv installation failed" >&2
  exit 1
fi

## Run parser via your wrapper script
./scripts/run-parser.sh \
  --input-file "${FEEDS_INPUT}" \
  --output-file "${OUTPUT_FILE}" \
  --timeout "${REQUEST_TIMEOUT}" \
  --retries "${REQUEST_RETRIES}" \
  --opml-title "${OPML_TITLE}"

if [[ ! -f "${OUTPUT_FILE}" ]]; then
  echo "[ERROR] Missing output: ${OUTPUT_FILE}" >&2
  exit 1
fi

## Fetch history and tags
git fetch --tags origin 2>/dev/null || true

## Bump version only if OPML changed
if ./scripts/version/opml-changed.sh; then
  if [[ ! -f ".version" ]]; then
    echo "0.1.0" >.version
  fi

  ## Detect bump type from git history and bump version file
  BUMP_TYPE="$(./scripts/version/detect-bump.sh)"
  ./scripts/version/bump-version.sh -t "${BUMP_TYPE}" -f .version
else
  echo "OPML has not changed since last release; skipping version bump."
fi

## Ensure commit script is executable
chmod +x scripts/gitlab/commit-changes.sh

GITLAB_TOKEN="$GITLAB_TOKEN" GITLAB_HOST="$GITLAB_HOST" ./scripts/gitlab/commit-changes.sh
