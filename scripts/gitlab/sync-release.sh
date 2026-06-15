#!/usr/bin/env bash
set -euo pipefail

#################################################
# Ensures a tag exists for the current version, #
# and a release exists for the current tag.     #
#################################################

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

git fetch origin --tags

## Read version
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "[ERROR] Missing version file: $VERSION_FILE"
  exit 1
fi

VERSION=$(cat "$VERSION_FILE")
TAG="release/v${VERSION}"
ASSET_NAME="feeds-v${VERSION}.opml"

echo "Target version: $VERSION"
echo "Target tag: $TAG"

## Ensure tag exists
if ! git ls-remote --tags origin | grep -q "refs/tags/${TAG}$"; then
  echo "Tag missing → creating $TAG"

  git config user.email "ci-bot@example.com"
  git config user.name "CI Bot"

  git tag "$TAG"
  git push origin "$TAG"
else
  echo "Tag exists: $TAG"
fi

## Ensure release exists
RELEASE_EXISTS=$(curl -s \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/releases/${TAG}" |
  jq -r '.tag_name // empty')

if [[ -z "$RELEASE_EXISTS" ]]; then
  echo "Release missing → creating release for $TAG"

  curl -s -X POST \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/releases" \
    -d "{
      \"name\": \"Release v${VERSION}\",
      \"tag_name\": \"${TAG}\",
      \"description\": \"OPML release v${VERSION}\",
      \"assets\": {
        \"links\": [
          {
            \"name\": \"${ASSET_NAME}\",
            \"url\": \"https://${GITLAB_HOST}/${CI_PROJECT_PATH}/-/raw/${TAG}/${OUTPUT_FILE}\"
          }
        ]
      }
    }"
else
  echo "Release already exists for $TAG"
fi

echo "Sync complete for $TAG"
