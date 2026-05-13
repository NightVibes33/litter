#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OWNER="${LITTER_BUILDKIT_ASSET_OWNER:-NightVibes33}"
REPO="${LITTER_BUILDKIT_ASSET_REPO:-litter-buildkit-assets}"
TAG="${LITTER_BUILDKIT_ASSET_TAG:-buildkit-ios26.4-v1}"
ASSET_PREFIX="${LITTER_BUILDKIT_ASSET_PREFIX:-LitterBuildKitAssets}"
PREFERRED_ASSET="${LITTER_BUILDKIT_EXISTING_ASSET_NAME:-LitterBuildKitAssets.zip}"
ZIP_PATH="${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}"
INFO_PATH="${LITTER_BUILDKIT_RELEASE_INFO:-${ROOT_DIR}/artifacts/buildkit/private-release-upload.txt}"
TOKEN="${LITTER_BUILDKIT_ASSET_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
API_URL="${GITHUB_API_URL:-https://api.github.com}"

if [[ -z "$TOKEN" ]]; then
  echo "No BuildKit asset token configured; cannot check private release." >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$(dirname "$ZIP_PATH")" "$(dirname "$INFO_PATH")"

status="$(curl -sS -o "$TMP_DIR/release.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API_URL/repos/$OWNER/$REPO/releases/tags/$TAG")"
if [[ "$status" != "200" ]]; then
  echo "No reusable BuildKit release found for $OWNER/$REPO@$TAG (HTTP $status)." >&2
  exit 2
fi

read -r ASSET_NAME ASSET_URL SHA_NAME SHA_URL < <(python3 - "$TMP_DIR/release.json" "$ASSET_PREFIX" "$PREFERRED_ASSET" <<'PYSELECT'
import json, sys
release_path, prefix, preferred = sys.argv[1:4]
with open(release_path, "r", encoding="utf-8") as fh:
    release = json.load(fh)
assets = release.get("assets", [])
zips = [
    asset for asset in assets
    if asset.get("name", "").startswith(prefix)
    and asset.get("name", "").endswith(".zip")
    and not asset.get("name", "").endswith(".sha256")
]
if not zips:
    raise SystemExit(2)
zips.sort(key=lambda asset: asset.get("updated_at") or asset.get("created_at") or "", reverse=True)
selected = next((asset for asset in zips if asset.get("name") == preferred), zips[0])
sha_name = selected["name"] + ".sha256"
sha_asset = next((asset for asset in assets if asset.get("name") == sha_name), {})
print(selected.get("name", ""), selected.get("url", ""), sha_asset.get("name", ""), sha_asset.get("url", ""))
PYSELECT
)

if [[ -z "$ASSET_NAME" || -z "$ASSET_URL" ]]; then
  echo "No reusable BuildKit ZIP asset found in $OWNER/$REPO@$TAG." >&2
  exit 2
fi

echo "==> Downloading existing BuildKit asset $ASSET_NAME"
curl -fsSL \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/octet-stream" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -o "$ZIP_PATH" \
  "$ASSET_URL"

SHA_VALUE="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
if [[ -n "$SHA_URL" ]]; then
  SHA_PATH="$TMP_DIR/$SHA_NAME"
  curl -fsSL \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/octet-stream" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -o "$SHA_PATH" \
    "$SHA_URL"
  EXPECTED_SHA="$(awk '{print $1}' "$SHA_PATH" | head -n 1)"
  if [[ -n "$EXPECTED_SHA" && "$EXPECTED_SHA" != "$SHA_VALUE" ]]; then
    echo "error: existing BuildKit asset SHA mismatch" >&2
    echo "expected=$EXPECTED_SHA actual=$SHA_VALUE" >&2
    exit 1
  fi
fi

"$ROOT_DIR/tools/scripts/verify-nyxian-buildkit-assets.sh" "$ZIP_PATH"

cat > "$INFO_PATH" <<EOF
BuildKit assets reused from private release.
Repo: $OWNER/$REPO
Tag: $TAG
Asset: $ASSET_NAME
SHA256: $SHA_VALUE
CI secrets:
  LITTER_BUILDKIT_ASSET_URL=$ASSET_URL
  LITTER_BUILDKIT_ASSET_SHA256=$SHA_VALUE
  LITTER_BUILDKIT_ASSET_TOKEN=<token with repo read access>
EOF

cat "$INFO_PATH"
