#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE=".version"
BUMP_TYPE="patch"

function usage() {
  cat <<EOF
Usage:
  $0 -t [patch|minor|major] -f <version-file>

Options:
  -t, --type          bump type (patch|minor|major)
  -f, --version-file  path to version file (default: .version)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -t | --type)
    BUMP_TYPE="$2"
    shift 2
    ;;
  -f | --version-file)
    VERSION_FILE="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown arg: $1"
    usage
    exit 1
    ;;
  esac
done

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "0.1.0" >"$VERSION_FILE"
fi

current_version=$(cat "$VERSION_FILE")

IFS='.' read -r major minor patch <<<"$current_version"

case "$BUMP_TYPE" in
major)
  major=$((major + 1))
  minor=0
  patch=0
  ;;
minor)
  minor=$((minor + 1))
  patch=0
  ;;
patch)
  patch=$((patch + 1))
  ;;
*)
  echo "Invalid bump type: $BUMP_TYPE"
  exit 1
  ;;
esac

new_version="${major}.${minor}.${patch}"

echo "$new_version" >"$VERSION_FILE"
echo "$new_version"
