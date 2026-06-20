#!/usr/bin/env bash
# package-perplexityai-assets.sh
# Packages the PerplexityAI runtime resources into a zip ready for iOS app bundle injection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.."; pwd)"

SOURCE_DIR="$REPO_ROOT/apps/ios/Sources/Litter/Resources/PerplexityAI"
OUT_DIR="$REPO_ROOT/artifacts/perplexityai"
ASSET_DIR="$OUT_DIR/LitterPerplexityAIAssets"
ZIP_OUT="$OUT_DIR/LitterPerplexityAIAssets.zip"
INSTALL_MARKER="$ASSET_DIR/.perplexityai-assets-version"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "error: PerplexityAI source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$ASSET_DIR"

echo "==> Copying PerplexityAI source tree..."
rm -rf "$ASSET_DIR/PerplexityAI"
cp -R "$SOURCE_DIR" "$ASSET_DIR/PerplexityAI"

echo "==> Building Python wheel from upstream source..."
PYPROJECT="$SOURCE_DIR/upstream/pyproject.toml"
if [ -f "$PYPROJECT" ]; then
  WHEEL_OUT="$ASSET_DIR/wheels"
  mkdir -p "$WHEEL_OUT"
  python3 -m pip wheel "$SOURCE_DIR/upstream" \
    --no-deps \
    --wheel-dir "$WHEEL_OUT" \
    --quiet
  echo "  Built wheels:"
  ls "$WHEEL_OUT"
fi

echo "==> Writing version marker..."
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y%m%d)"
cat > "$INSTALL_MARKER" <<EOF
perplexityai-assets-version=1
git-sha=$GIT_SHA
build-date=$DATE
EOF

echo "==> Zipping asset pack..."
rm -f "$ZIP_OUT"
(cd "$OUT_DIR" && zip -qry "LitterPerplexityAIAssets.zip" "LitterPerplexityAIAssets")

echo "==> Done: $ZIP_OUT"
du -sh "$ZIP_OUT"
