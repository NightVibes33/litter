#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OWNER="${LITTER_BUILDKIT_ASSET_OWNER:-NightVibes33}"
REPO="${LITTER_BUILDKIT_ASSET_REPO:-litter-buildkit-assets}"
TAG="${LITTER_BUILDKIT_ASSET_TAG:-buildkit-ios26.4-v1}"
RELEASE_NAME="${LITTER_BUILDKIT_ASSET_RELEASE_NAME:-Litter BuildKit Assets iOS 26.4}"
ZIP_PATH="${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}"
ASSET_NAME="${LITTER_BUILDKIT_ASSET_NAME:-LitterBuildKitAssets.zip}"
TOKEN="${LITTER_BUILDKIT_ASSET_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
API_URL="${GITHUB_API_URL:-https://api.github.com}"
UPLOAD_URL="${GITHUB_UPLOAD_URL:-https://uploads.github.com}"

if [[ -z "$TOKEN" ]]; then
  echo "error: set LITTER_BUILDKIT_ASSET_TOKEN, GITHUB_TOKEN, or GH_TOKEN" >&2
  exit 1
fi
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "error: BuildKit asset zip not found: $ZIP_PATH" >&2
  echo "Run tools/scripts/package-buildkit-assets.sh on macOS first." >&2
  exit 1
fi


sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SHA_PATH="$TMP_DIR/${ASSET_NAME}.sha256"
SHA_VALUE="$(sha256_file "$ZIP_PATH")"
printf '%s  %s\n' "$SHA_VALUE" "$ASSET_NAME" > "$SHA_PATH"

api_curl() {
  curl -fsSL \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

json_field() {
  python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get(sys.argv[1], ""))' "$1"
}

asset_id_for_name() {
  python3 - "$1" "$TMP_DIR/release.json" <<'PYASSET'
import json, sys
name = sys.argv[1]
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    data = json.load(fh)
for asset in data.get("assets", []):
    if asset.get("name") == name:
        print(asset.get("id", ""))
        break
PYASSET
}

ensure_repo() {
  local status
  status="$(curl -sS -o "$TMP_DIR/repo.json" -w '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/repos/$OWNER/$REPO")"
  if [[ "$status" == "200" ]]; then
    return
  fi
  if [[ "$status" != "404" ]]; then
    echo "error: GitHub repo lookup failed with HTTP $status" >&2
    cat "$TMP_DIR/repo.json" >&2 || true
    exit 1
  fi
  echo "==> Creating private repo $OWNER/$REPO" >&2
  api_curl -X POST "$API_URL/user/repos" \
    -d "{\"name\":\"$REPO\",\"private\":true,\"description\":\"Private Litter BuildKit compiler/SDK assets\"}" \
    > "$TMP_DIR/repo-create.json"
}

ensure_release() {
  local status
  status="$(curl -sS -o "$TMP_DIR/release.json" -w '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/repos/$OWNER/$REPO/releases/tags/$TAG")"
  if [[ "$status" == "200" ]]; then
    json_field id < "$TMP_DIR/release.json"
    return
  fi
  if [[ "$status" != "404" ]]; then
    echo "error: GitHub release lookup failed with HTTP $status" >&2
    cat "$TMP_DIR/release.json" >&2 || true
    exit 1
  fi
  echo "==> Creating release $TAG" >&2
  api_curl -X POST "$API_URL/repos/$OWNER/$REPO/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"$RELEASE_NAME\",\"prerelease\":false,\"draft\":false}" \
    > "$TMP_DIR/release.json"
  json_field id < "$TMP_DIR/release.json"
}

delete_existing_asset() {
  local name="$1"
  local id
  id="$(asset_id_for_name "$name")"
  if [[ -n "$id" ]]; then
    echo "==> Replacing existing asset $name"
    api_curl -X DELETE "$API_URL/repos/$OWNER/$REPO/releases/assets/$id" >/dev/null
  fi
}

upload_asset() {
  local release_id="$1"
  local file_path="$2"
  local name="$3"
  local content_type="$4"
  delete_existing_asset "$name"
  echo "==> Uploading $name"
  curl -fsSL \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: $content_type" \
    --data-binary "@$file_path" \
    "$UPLOAD_URL/repos/$OWNER/$REPO/releases/$release_id/assets?name=$name" \
    > "$TMP_DIR/upload-$name.json"
}

ensure_repo
RELEASE_ID="$(ensure_release)"
upload_asset "$RELEASE_ID" "$ZIP_PATH" "$ASSET_NAME" "application/zip"
upload_asset "$RELEASE_ID" "$SHA_PATH" "${ASSET_NAME}.sha256" "text/plain"

ASSET_ID="$(json_field id < "$TMP_DIR/upload-$ASSET_NAME.json")"
ASSET_API_URL="$API_URL/repos/$OWNER/$REPO/releases/assets/$ASSET_ID"
cat <<EOF
BuildKit assets uploaded.
Repo: $OWNER/$REPO
Tag: $TAG
Asset: $ASSET_NAME
SHA256: $SHA_VALUE
CI secrets:
  LITTER_BUILDKIT_ASSET_URL=$ASSET_API_URL
  LITTER_BUILDKIT_ASSET_SHA256=$SHA_VALUE
  LITTER_BUILDKIT_ASSET_TOKEN=<token with repo read access>
EOF
