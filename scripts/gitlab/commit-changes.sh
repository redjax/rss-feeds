#!/usr/bin/env bash
set -euo pipefail

## Load GitLab variables from the job environment
: "${GITLAB_TOKEN:?GITLAB_TOKEN is missing}"
: "${GITLAB_HOST:?GITLAB_HOST is missing}"
: "${CI_PROJECT_PATH:?CI_PROJECT_PATH is missing}"
: "${CI_PROJECT_ID:?CI_PROJECT_ID is missing}"
: "${CI_COMMIT_SHORT_SHA:?CI_COMMIT_SHORT_SHA is missing}"
: "${CI_DEFAULT_BRANCH:=main}"

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${THIS_DIR}/../../" && pwd -P)"
cd "${REPO_ROOT}"

## Ensure .local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

git remote set-url origin "https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${CI_PROJECT_PATH}.git"

OUTPUT_DIR="${OUTPUT_DIR:-output}"
OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"

UPDATE_BRANCH="chore/update-feeds-${CI_COMMIT_SHORT_SHA}"

git config --global user.email "ci-bot@example.com"
git config --global user.name "CI Bot"
git checkout -b "$UPDATE_BRANCH"

## Commit OPML
git add "${OUTPUT_DIR}/${OUTPUT_FILE}"

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
  -o merge_request.description="This PR auto-updates feeds.opml because feeds.yml changed on main." \
  -o merge_request.merge_when_pipeline_succeeds=true \
  -o merge_request.remove_source_branch=true

echo "MR created and configured for auto-merge when pipeline succeeds: ${UPDATE_BRANCH}"
