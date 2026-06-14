#!/usr/bin/env bash
set -euo pipefail

if command -v uv >/dev/null 2>&1; then
  echo "uv is already installed."
  exit 0
fi

if command -v curl >/dev/null 2>&1; then
  echo "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh >&2
  LAST_EXIT=$?

  if [[ $LAST_EXIT -ne 0 ]]; then
    echo "[ERROR] Failed to install uv." >&2
  fi

elif command -v wget >/dev/null 2>&1; then
  echo "Installing uv"
  wget -qO- https://astral.sh/uv/install.sh | sh >&2
  LAST_EXIT=$?

  if [[ $LAST_EXIT -ne 0 ]]; then
    echo "[ERROR] Failed to install uv." >&2
  fi

else
  echo "[ERROR] Missing both curl & wget. Install one or both and try again." >&2
  exit 1
fi
