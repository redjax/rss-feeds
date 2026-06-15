#!/usr/bin/env bash
set -euo pipefail

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(realpath -m "${THIS_DIR}/..")"
PARSER_DIR="${REPO_ROOT}/scripts/parser"
INSTALL_UV_SCRIPT="${REPO_ROOT}/scripts/install/install-uv.sh"

CWD="$(pwd)"

trap 'cd "${CWD}"' EXIT

FEEDS_FILE=".raw/feeds.yml"
OUTPUT_FILE="feeds.opml"
REQUEST_TIMEOUT=10
REQUEST_RETRIES=3
OPML_TITLE="My RSS Feeds"

DEBUG=false
DRY_RUN=false

## Ensure .local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

function debug() {
  if [[ "${DEBUG}" == "true" ]]; then
    echo "[DEBUG] $*"
  fi
}

function usage() {
  cat <<EOF
Usage:
  $0 [OPTIONS]

Options:
  -i, --input-file   <path>   Input feeds.yml (default: .raw/feeds.yml)
  -O, --output-file  <file>   Output OPML file (default: feeds.opml)
  -r, --retries      <int>    Retries
  -t, --timeout      <int>    Timeout
  -T, --opml-title   <str>    OPML title
  --dry-run                   Show command only
  --debug                     Enable debug
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
  -i | --input-file)
    FEEDS_FILE="$2"
    shift 2
    ;;
  -O | --output-file)
    OUTPUT_FILE="$2"
    shift 2
    ;;
  -r | --retries)
    REQUEST_RETRIES="$2"
    shift 2
    ;;
  -t | --timeout)
    REQUEST_TIMEOUT="$2"
    shift 2
    ;;
  -T | --opml-title)
    OPML_TITLE="$2"
    shift 2
    ;;
  --debug)
    DEBUG=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  *)
    echo "Invalid arg: $1" >&2
    exit 1
    ;;
  esac
done

## Ensure uv is installed
if [[ ! -f "${INSTALL_UV_SCRIPT}" ]]; then
  echo "[ERROR] install-uv.sh not found" >&2
  exit 1
fi

"${INSTALL_UV_SCRIPT}"

## Ensure uv is available in PATH immediately
export PATH="$HOME/.local/bin:$PATH"

cd "${REPO_ROOT}"

## Validate inputs
if [[ ! -f "${REPO_ROOT}/${FEEDS_FILE}" ]]; then
  echo "[ERROR] Missing input file: ${FEEDS_FILE}" >&2
  exit 1
fi

parse_cmd=(
  uv run
  --project "${PARSER_DIR}"
  python "${PARSER_DIR}/parse_feeds.py"
  --input "${REPO_ROOT}/${FEEDS_FILE}"
  --output-file "${REPO_ROOT}/${OUTPUT_FILE}"
  --timeout "${REQUEST_TIMEOUT}"
  --retries "${REQUEST_RETRIES}"
  --title "${OPML_TITLE}"
)

echo "Generating OPML, outputting to: ${OUTPUT_FILE}"
echo

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY RUN] ${parse_cmd[*]}"
  exit 0
fi

debug "Running: ${parse_cmd[*]}"

"${parse_cmd[@]}"
