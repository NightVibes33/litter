#!/usr/bin/env bash
# download-perplexityai-assets-release.sh
# Downloads and verifies the PerplexityAI asset zip from the private release.
# Used by iOS build workflows to inject assets before xcodebuild.
# Exit 0 = success, exit 2 = not found (caller can skip), exit 1 = hard error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.."; pwd)"

OUT_DIR="$REPO_ROOT/artifacts/perplexityai"
mkdir -p "$OUT_DIR"

ASSET_URL="${LITTER_PERPLEXITY_ASSET_URL:-}"
ASSET_SHA256="${LITTER_PERPLEXITY_ASSET_SHA256:-}"
ASSET_TOKEN="${LITTER_PERPLEXITY_ASSET_TOKEN:-}"
DEST="$OUT_DIR/LitterPerplexityAIAssets.zip"

if [ -z "$ASSET_URL" ] || [ -z "$ASSET_SHA256" ]; then
  echo "info: LITTER_PERPLEXITY_ASSET_URL or LITTER_PERPLEXITY_ASSET_SHA256 not set — skipping download."
  exit 2
fi

if [ -z "$ASSET_TOKEN" ]; then
  echo "error: LITTER_PERPLEXITY_ASSET_TOKEN is required for private release download." >&2
  exit 1
fi

echo "==> Downloading PerplexityAI assets from: $ASSET_URL"
curl -fsSL -L \
  -H "Authorization: token $ASSET_TOKEN" \
  -o "$DEST" \
  "$ASSET_URL"

echo "==> Verifying SHA-256..."
ACTUAL_SHA="$(shasum -a 256 "$DEST" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$ASSET_SHA256" ]; then
  echo "error: SHA-256 mismatch!" >&2
  echo "  expected: $ASSET_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA" >&2
  exit 1
fi
echo "  SHA-256 OK: $ACTUAL_SHA"

"$SCRIPT_DIR/verify-perplexityai-assets.sh" "$DEST"

echo "==> Extracting assets into resource bundle..."
TARGET_DIR="$REPO_ROOT/apps/ios/Sources/Litter/Resources"
unzip -qo "$DEST" -d "$TARGET_DIR"

echo "==> PerplexityAI assets ready at $TARGET_DIR/LitterPerplexityAIAssets"
