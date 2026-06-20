#!/usr/bin/env bash
# verify-perplexityai-assets.sh <path-to-zip>
# Verifies the PerplexityAI asset zip contains the expected structure.
set -euo pipefail

ZIP_PATH="${1:-}"
if [ -z "$ZIP_PATH" ] || [ ! -f "$ZIP_PATH" ]; then
  echo "error: usage: $0 <path-to-LitterPerplexityAIAssets.zip>" >&2
  exit 1
fi

echo "==> Verifying PerplexityAI asset pack: $ZIP_PATH"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unzip -q "$ZIP_PATH" -d "$TMP_DIR"

check_path() {
  local path="$TMP_DIR/LitterPerplexityAIAssets/$1"
  if [ ! -e "$path" ]; then
    echo "error: expected path missing in asset pack: $1" >&2
    exit 1
  fi
  echo "  OK: $1"
}

check_path "PerplexityAI/bin"
check_path "PerplexityAI/upstream"
check_path ".perplexityai-assets-version"

echo "==> Asset pack verified OK."
