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

git fetch --unshallow 2>/dev/null || true

OUTPUT_FILE="${OUTPUT_FILE:-feeds.opml}"

UPDATE_BRANCH="chore/update-feeds"

git config --global user.email "ci-bot@example.com"
git config --global user.name "CI Bot"

## Ensure generated file exists
if [[ ! -f "${OUTPUT_FILE}" ]]; then
  echo "[ERROR] Missing generated file: ${OUTPUT_FILE}" >&2
  exit 1
fi

## Create isolated worktree for update branch
WORKTREE_DIR="$(mktemp -d)"

cleanup() {
  git worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || true
  rm -rf "${WORKTREE_DIR}" 2>/dev/null || true
}

trap cleanup EXIT

## Synchronize existing branch if one exists
if git ls-remote --exit-code origin "${UPDATE_BRANCH}" >/dev/null 2>&1; then
  echo "Remote branch exists, syncing"

  git fetch origin "${UPDATE_BRANCH}"

  git worktree add \
    "${WORKTREE_DIR}" \
    -B "${UPDATE_BRANCH}" \
    "origin/${UPDATE_BRANCH}"
else
  echo "No remote branch yet, creating fresh one"

  git worktree add \
    -b "${UPDATE_BRANCH}" \
    "${WORKTREE_DIR}"
fi

## Copy generated OPML into update branch worktree
cp "${OUTPUT_FILE}" "${WORKTREE_DIR}/${OUTPUT_FILE}"

cd "${WORKTREE_DIR}"

## Commit OPML
git add "${OUTPUT_FILE}"

## Avoid failing pipeline if nothing changed
if git diff --cached --quiet; then
  echo "No changes to commit. Exiting."
  exit 0
fi

git commit -m "chore: update feeds.opml (auto-generated)"

## Push branch & create MR with auto-merge enabled
git push -u origin "${UPDATE_BRANCH}" \
  -o merge_request.create \
  -o merge_request.title="chore: update feeds.opml (auto-generated)" \
  -o merge_request.description="This PR auto-updates feeds.opml because .raw/feeds.yml changed." \
  -o merge_request.merge_when_pipeline_succeeds=true \
  -o merge_request.remove_source_branch=true

echo "Created (or updated) merge request: ${UPDATE_BRANCH}"
