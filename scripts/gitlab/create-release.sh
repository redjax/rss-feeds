#!/usr/bin/env bash
set -euo pipefail

: "${GITLAB_TOKEN:?missing}"
: "${GITLAB_HOST:?missing}"
: "${CI_PROJECT_ID:?missing}"
: "${CI_PROJECT_PATH:?missing}"

VERSION_FILE="${VERSION_FILE:-.version}"
OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"
BASE_BRANCH="${BASE_BRANCH:-main}"

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../../" && pwd -P)"
cd "${REPO_ROOT}"

git remote set-url origin "https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${CI_PROJECT_PATH}.git"

git fetch origin --tags

## Skip if no OPML change since last release
if ! ./scripts/version/opml-changed.sh; then
  echo "No OPML changes since last release → skipping release"
  exit 0
fi

## Detect bump type (major, minor, patch) from git changes
BUMP_TYPE=$(./scripts/version/detect-bump.sh || echo "patch")
echo "Detected bump type: $BUMP_TYPE"

## Bump version
NEW_VERSION=$(
  ./scripts/version/bump_version.sh \
    -t "$BUMP_TYPE" \
    -f "$VERSION_FILE"
)

echo "New version: $NEW_VERSION"

TAG="release/v${NEW_VERSION}"
ASSET_NAME="feeds-v${NEW_VERSION}.opml"

## Avoid duplicate tags
if git ls-remote --tags origin | grep -q "refs/tags/${TAG}$"; then
  echo "Tag already exists: $TAG"
  exit 0
fi

## Create git tag & push
git config user.email "ci-bot@example.com"
git config user.name "CI Bot"

git tag "$TAG"
git push origin "$TAG"

## Create GitLab release
curl -s -X POST \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/releases" \
  -d "{
    \"name\": \"Release v${NEW_VERSION}\",
    \"tag_name\": \"${TAG}\",
    \"description\": \"OPML release v${NEW_VERSION}\",
    \"assets\": {
      \"links\": [
        {
          \"name\": \"${ASSET_NAME}\",
          \"url\": \"https://${GITLAB_HOST}/${CI_PROJECT_PATH}/-/raw/${TAG}/${OUTPUT_FILE}\"
        }
      ]
    }
  }"

echo "Release created: ${TAG}"
