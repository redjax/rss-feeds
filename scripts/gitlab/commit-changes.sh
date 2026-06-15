#!/usr/bin/env bash
set -euo pipefail

## Load GitLab variables from the job environment
: "${GITLAB_TOKEN:?GITLAB_TOKEN is missing}"
: "${GITLAB_HOST:?GITLAB_HOST is missing}"
: "${CI_PROJECT_PATH:?CI_PROJECT_PATH is missing}"
: "${CI_PROJECT_ID:?CI_PROJECT_ID is missing}"

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../../" && pwd -P)"
cd "${REPO_ROOT}"

git remote set-url origin "https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${CI_PROJECT_PATH}.git"

OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"

UPDATE_BRANCH="chore/update-feeds"

git config --global user.email "ci-bot@example.com"
git config --global user.name "CI Bot"

## Synchronize existing branch if one exists
if git ls-remote --exit-code origin "$UPDATE_BRANCH" >/dev/null 2>&1; then
  echo "Remote branch exists, syncing"
  git fetch origin "$UPDATE_BRANCH"
  git checkout "$UPDATE_BRANCH"
  git reset --hard "origin/$UPDATE_BRANCH"
else
  echo "No remote branch yet, creating fresh one"
  git checkout -B "$UPDATE_BRANCH"
fi

## Commit OPML
git add "${OUTPUT_FILE}"

## Avoid failing pipeline if nothing changed
if git diff --cached --quiet; then
  echo "No changes to commit. Exiting."
  exit 0
fi

git commit -m "chore: update feeds.opml (auto-generated)"

## Push branch & create MR with auto-merge enabled
git push -u origin "$UPDATE_BRANCH" \
  -o merge_request.create \
  -o merge_request.title="chore: update feeds.opml (auto-generated)" \
  -o merge_request.description="This PR auto-updates feeds.opml because .raw/feeds.yml changed." \
  -o merge_request.merge_when_pipeline_succeeds=true \
  -o merge_request.remove_source_branch=true

echo "Created (or updated) merge request: $UPDATE_BRANCH"
