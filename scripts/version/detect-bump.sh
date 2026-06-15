#!/usr/bin/env bash
set -euo pipefail

BASE_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -z "$BASE_TAG" ]]; then
  BASE_TAG=$(git rev-list --max-parents=0 HEAD)
fi

COMMITS=$(git log "${BASE_TAG}..HEAD" --pretty=format:%s)

if [[ -z "$COMMITS" ]]; then
  echo "patch"
  exit 0
fi

BUMP="patch"

while IFS= read -r msg; do

  ## major vX.0.0
  if [[ "$msg" =~ ^feat\!\: ]] || [[ "$msg" =~ BREAKING[[:space:]]CHANGE ]]; then
    BUMP="major"
    break
  fi

  ## minor v0.X.0
  if [[ "$msg" =~ ^feat\: ]]; then
    if [[ "$BUMP" != "major" ]]; then
      BUMP="minor"
    fi
  fi

  ## patch v0.0.X
  if [[ "$msg" =~ ^fix\: ]]; then
    if [[ "$BUMP" == "patch" ]]; then
      BUMP="patch"
    fi
  fi

done <<<"$COMMITS"

echo "$BUMP"
