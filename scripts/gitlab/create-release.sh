#!/usr/bin/env bash
set -euo pipefail

: "${GITLAB_TOKEN:?missing}"
: "${GITLAB_HOST:?missing}"
: "${CI_PROJECT_ID:?missing}"
: "${CI_PROJECT_PATH:?missing}"

VERSION_FILE="${VERSION_FILE:-.version}"
OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../../" && pwd -P)"
cd "${REPO_ROOT}"

git remote set-url origin "https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${CI_PROJECT_PATH}.git"

## Verify artifacts exist
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "[ERROR] Missing version file: $VERSION_FILE" >&2
  exit 1
fi

if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "[ERROR] Missing OPML file: $OUTPUT_FILE" >&2
  exit 1
fi

VERSION=$(cat "$VERSION_FILE")

TAG="release/v${VERSION}"
ASSET_NAME="feeds-v${VERSION}.opml"

echo "Release version: $VERSION"
echo "Tag: $TAG"

## Fetch tags from remote
git fetch --prune --tags origin

## Avoid duplicate tags
if git ls-remote --tags origin | grep -q "refs/tags/${TAG}$"; then
  echo "Tag already exists: $TAG, skipping"
  exit 0
fi

## Create tag
git config user.email "ci-bot@example.com"
git config user.name "CI Bot"

git tag "$TAG"
git push origin "$TAG"

## Upload feeds.opml as release asset
PACKAGE_NAME="feeds-opml"
PACKAGE_FILE="feeds-v${VERSION}.opml"

echo "Uploading OPML as package asset..."

ASSET_FULL_URL="https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${VERSION}/${PACKAGE_FILE}"

curl -sS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --upload-file "${OUTPUT_FILE}" \
  "${ASSET_FULL_URL}"

echo "Uploaded asset: ${ASSET_FULL_URL}"

## Create release
curl -sS -X POST \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/releases" \
  --data-raw "{
    \"name\": \"Release v${VERSION}\",
    \"tag_name\": \"${TAG}\",
    \"description\": \"OPML release v${VERSION}\",
    \"assets\": {
      \"links\": [
        {
          \"name\": \"${ASSET_NAME}\",
          \"url\": \"${ASSET_FULL_URL}\"
        }
      ]
    }
  }"

echo "Release created: ${TAG}"
