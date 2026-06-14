#!/usr/bin/env bash
set -euo pipefail

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT=$(realpath -m "${THIS_DIR}/..")
SCRIPTS_DIR="${REPO_ROOT}/scripts"
INSTALL_UV_SCRIPT="${SCRIPTS_DIR}/install/install-uv.sh"
PARSE_SCRIPT="${SCRIPTS_DIR}/parse_feeds.py"
DEBUG=false
DRY_RUN=false

CWD="$(pwd)"

FEEDS_FILE="feeds.yml"
OUTPUT_DIR="output"
OUTPUT_FILE="feeds.opml"
REQUEST_TIMEOUT=10
REQUEST_RETRIES=3
OPML_TITLE="My RSS Feeds"

function cleanup() {
  cd "${CWD}"
}
trap cleanup EXIT

function usage() {
  cat <<EOF
Usage:
  ${0} [OPTIONS]

Options:
  -h, --help                Print this help menu
  -i, --input-file  <path>  Path to a feeds.yml file to use as the raw input
  -o, --output-dir  <path>  Path to a directory where OPML file will be rendered
  -O, --output-file <str>   Name of output filename (default: feeds.opml)
  -r, --retries     <int>   Number of HTTP request retries
  -t, --timeout     <int>   Number of seconds before HTTP request times out (default: 10)
  -T, --opml-title  <str>   Name of OPML feed
  --dry-run                 Print uv command without running it
  --debug                   When present, debug messages will print
EOF
}

function debug() {
  if [[ "${DEBUG}" == "true" ]]; then
    echo "[DEBUG] $*"
  fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  -i | --input-file)
    FEEDS_FILE="$2"
    shift 2
    ;;
  -o | --output-dir)
    OUTPUT_DIR="$2"
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
    DEBUG="true"
    shift
    ;;
  --dry-run)
    DRY_RUN="true"
    shift
    ;;
  *)
    echo "[ERROR] Invalid arg: ${1}" >&2
    usage
    exit 1
    ;;
  esac
done

## Ensure uv is installed
if ! "${INSTALL_UV_SCRIPT}" >&2; then
  echo "[ERROR] uv was not found and automatic installation failed" >&2
  exit 1
fi

cd "${REPO_ROOT}"

## Validate inputs
if [[ "${FEEDS_FILE}" == "" ]]; then
  echo "[ERROR] Missing --input-file" >&2
  usage
  exit 1
fi

if [[ ! -f "${FEEDS_FILE}" ]]; then
  echo "[ERROR] Could not find input file at path: ${FEEDS_FILE}" >&2
  usage
  exit 1
fi

if [[ "${REQUEST_TIMEOUT}" == "" ]]; then
  echo "[ERROR] Missing --timeout" >&2
  usage
  exit 1
fi

if [[ "${REQUEST_RETRIES}" == "" ]]; then
  echo "[ERROR] Missing --retries" >&2
  usage
  exit 1
fi

if [[ "${OPML_TITLE}" == "" ]]; then
  echo "[ERROR] Missing --opml-title" >&2
  usage
  exit 1
fi

if [[ "${OUTPUT_DIR}" == "" ]]; then
  echo "[ERROR] Missing --output-dir" >&2
  usage
  exit 1
fi

mkdir -p "${OUTPUT_DIR}" >&2 || true

if [[ "${OUTPUT_FILE}" == "" ]]; then
  echo "[ERROR] Missing --output-file" >&2
  usage
  exit 1
fi

if [[ -f "${OUTPUT_FILE}" ]]; then
  echo "[WARNING] Output file already exists and will be overwritten: ${OUTPUT_FILE}"
fi

if [[ ! -f "${PARSE_SCRIPT}" ]]; then
  echo "[ERROR] Could not find feed parsing script at path: ${PARSE_SCRIPT}" >&2
  exit 1
fi

parse_cmd=(uv run "${PARSE_SCRIPT}")
parse_cmd+=(--input "${FEEDS_FILE}")
parse_cmd+=(--output-dir "${OUTPUT_DIR}")
parse_cmd+=(--output-file "${OUTPUT_FILE}")
parse_cmd+=(--timeout "${REQUEST_TIMEOUT}")
parse_cmd+=(--retries "${REQUEST_RETRIES}")
parse_cmd+=(--title "${OPML_TITLE}")

echo "Parsing input file '${FEEDS_FILE}' into OPML file at path: ${OUTPUT_DIR}/${OUTPUT_FILE}"
echo

if [[ "$DRY_RUN" == "false" ]]; then
  debug "Command:
    ${parse_cmd[*]}
  "
else
  echo "[DRY RUN] Would run command:
  ${parse_cmd[*]}
"

  exit 0
fi

"${parse_cmd[@]}"
