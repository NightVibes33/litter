#!/usr/bin/env bash
# upload-perplexityai-assets-release.sh
# Creates/updates a private GitHub release and uploads the PerplexityAI asset zip.
# Mirrors the pattern of upload-buildkit-assets-release.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.."; pwd)"

OUT_DIR="$REPO_ROOT/artifacts/perplexityai"
ZIP_PATH="$OUT_DIR/LitterPerplexityAIAssets.zip"
SHA256_PATH="$OUT_DIR/LitterPerplexityAIAssets.zip.sha256"

if [ ! -f "$ZIP_PATH" ]; then
  echo "error: asset zip not found at $ZIP_PATH" >&2
  exit 1
fi

if [ -z "${LITTER_PERPLEXITY_ASSET_TOKEN:-}" ]; then
  echo "error: LITTER_PERPLEXITY_ASSET_TOKEN is not set" >&2
  exit 1
fi

OWNER="${LITTER_PERPLEXITY_ASSET_OWNER:-NightVibes33}"
REPO="${LITTER_PERPLEXITY_ASSET_REPO:-litter-perplexityai-assets}"
TAG="${LITTER_PERPLEXITY_ASSET_TAG:-perplexityai-v1}"
RELEASE_NAME="${LITTER_PERPLEXITY_ASSET_RELEASE_NAME:-Litter PerplexityAI Assets $TAG}"
ASSD_NAME="${LITTER_PERPLEXITY_ASSET_NAME:-LitterPerplexityAIAssets.zip}"

GH_AUTH="Authorization: token $LITTER_PERPLEXITY_ASSET_TOKEN"
API="https://api.github.com"

echo "==> Checking for existing release '$TAG' in $OWNER/$REPO..."
RELEASE_JSON="$(curl -fsSL -H "$GH_AUTH" \
  "$API/repos/$OWNER/$REPO/releases/tags/$TAG" 2>/dev/null || true)"

if echo "$RELEASE_JSON" | grep -q '"id"'; then
  RELEASE_ID="$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")"
  echo "  Found existing release id=$RELEASE_ID"
else
  echo "==> Creating release '$TAG'..."
  RELEASE_JSON="$(curl -fsSL -X POST -H "$GH_AUTH" \
    -H "Content-Type: application/json" \
    "$API/repos/$OWNER/$REPO/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"$RELEASE_NAME\",\"draft\":false,\"prerelease\":false}")"
  RELEASE_ID="$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")"
  echo "  Created release id=$RELEASE_ID"
fi

# Delete any existing asset with the same prefix to avoid duplicates
echo "==> Removing old assets with prefix '${LITTER_PERPLEXITY_ASSET_PREFIX:-LitterPerplexityAIAssets}'..."
ASSETS_JSON="$(curl -fsSL -H "$GH_AUTH" \
  "$API/repos/$OWNER/$REPO/releases/$RELEASE_ID/assets")"
echo "$ASSETS_JSON" | python3 - <<'PYEOF'
import sys, json, subprocess, os
data = json.load(sys.stdin)
prefix = os.environ.get('LITTER_PERPLEXITY_ASSET_PREFIX', 'LitterPerplexityAIAssets')
token = os.environ['LITTER_PERPLEXITY_ASSET_TOKEN']
owner = os.environ.get('LITTER_PERPLEXITY_ASSET_OWNER', 'NightVibes33')
repo = os.environ.get('LITTER_PERPLEXITY_ASSET_REPO', 'litter-perplexityai-assets')
for asset in data:
    if asset['name'].startswith(prefix):
        print(f"  Deleting old asset: {asset['name']} (id={asset['id']})")
        subprocess.run(['curl', '-fsSL', '-X', 'DELETE',
            '-H', f'Authorization: token {token}',
            f'https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset["id"]}'],
            check=True, capture_output=True)
PYEOF

echo "==> Uploading $ASSD_NAME..."
UPLOAD_URL="https://uploads.github.com/repos/$OWNER/$REPO/releases/$RELEASE_ID/assets?name=$ASSD_NAME"
UPLOAD_JSON="$(curl -fsSL -X POST -H "$GH_AUTH" \
  -H "Content-Type: application/zip" \
  --data-binary @"$ZIP_PATH" \
  "$UPLOAD_URL")"

ASSET_URL="$(echo "$UPLOAD_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['browser_download_url'])")"
ASS_SHA256="$(awk '{print $1}' "$SHA256_PATH")"

echo "LITTER_PERPLEXITY_ASSET_URL=$ASSET_URL"
echo "LITTER_PERPLEXITY_ASSET_SHA256=$ASS_SHA256"
echo "==> Upload complete: $ASSET_URL"
