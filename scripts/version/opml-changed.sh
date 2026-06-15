#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE="feeds.opml"

LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -z "$LAST_TAG" ]]; then
  exit 0
fi

## Check if OPML changed since last release
if git diff "$LAST_TAG"..HEAD -- "$OUTPUT_FILE" | grep -q .; then
  exit 0 # changed
else
  exit 1 # no change
fi
