#!/usr/bin/env bash
set -euo pipefail

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../.." && pwd -P)"
cd "${REPO_ROOT}"

OUTPUT_DIR="${OUTPUT_DIR:-output}"
OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"

GITLAB_TOKEN="${GITLAB_TOKEN}"
GITLAB_HOST="${GITLAB_HOST}"
CI_PROJECT_ID="${CI_PROJECT_ID}"
CI_COMMIT_SHORT_SHA="${CI_COMMIT_SHORT_SHA:-$(git rev-parse --short HEAD)}"
CI_DEFAULT_BRANCH="${CI_DEFAULT_BRANCH:-main}"

UPDATE_BRANCH="chore/update-feeds-${CI_COMMIT_SHORT_SHA}"

git config --global user.email "ci-bot@example.com"
git config --global user.name "CI Bot"
git checkout -b "$UPDATE_BRANCH"

## Commit OPML
git add "${OUTPUT_DIR}/${OUTPUT_FILE}"
git commit -m "chore: update feeds.opml (auto-generated)"

## Push branch
git push -u origin "$UPDATE_BRANCH"

## Create PR
PR_TITLE="chore: update feeds.opml (auto-generated)"
PR_DESC="This PR auto-updates feeds.opml because feeds.yml changed on main."

curl -X POST \
  -H "Authorization: Bearer ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/merge_requests" \
  -d "{
    \"source_branch\": \"${UPDATE_BRANCH}\",
    \"target_branch\": \"${CI_DEFAULT_BRANCH}\",
    \"title\": \"${PR_TITLE}\",
    \"description\": \"${PR_DESC}\",
    \"remove_source_branch\": true
  }"

## Auto-merge PR
MR_IID=$(curl -s \
  -H "Authorization: Bearer ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/merge_requests?source_branch=${UPDATE_BRANCH}" |
  jq -r '.[0].iid')

if [[ -n "$MR_IID" && "$MR_IID" != "null" ]]; then
  curl -X PUT \
    -H "Authorization: Bearer ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://${GITLAB_HOST}/api/v4/projects/${CI_PROJECT_ID}/merge_requests/${MR_IID}/merge" \
    -d "{\"should_remove_source_branch\": true}"
else
  echo "[WARNING] Could not find MR for branch ${UPDATE_BRANCH}"
fi
