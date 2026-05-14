#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/../.." && pwd)"
DEST="$IOS_DIR/Sources/Litter/Resources/BuildKitAssets"
ASSET_DIR="${LITTER_BUILDKIT_ASSET_DIR:-}"
ASSET_ZIP="${LITTER_BUILDKIT_ASSET_ZIP:-}"
ASSET_URL="${LITTER_BUILDKIT_ASSET_URL:-}"
ASSET_SHA256="${LITTER_BUILDKIT_ASSET_SHA256:-}"
ASSET_TOKEN="${LITTER_BUILDKIT_ASSET_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$ASSET_URL" ]]; then
  ASSET_ZIP="$TMP_DIR/LitterBuildKitAssets.zip"
  echo "==> Downloading private BuildKit assets"
  curl_args=(-fsSL --retry 3 -o "$ASSET_ZIP")
  if [[ -n "$ASSET_TOKEN" ]]; then
    curl_args+=(-H "Authorization: Bearer $ASSET_TOKEN")
    curl_args+=(-H "X-GitHub-Api-Version: 2022-11-28")
  fi
  if [[ "$ASSET_URL" == *"api.github.com"*"/releases/assets/"* ]]; then
    curl_args+=(-H "Accept: application/octet-stream")
  fi
  curl "${curl_args[@]}" "$ASSET_URL"
fi

if [[ -n "$ASSET_ZIP" ]]; then
  if [[ ! -f "$ASSET_ZIP" ]]; then
    echo "error: LITTER_BUILDKIT_ASSET_ZIP does not exist: $ASSET_ZIP" >&2
    exit 1
  fi
  if [[ -n "$ASSET_SHA256" ]]; then
    actual="$(shasum -a 256 "$ASSET_ZIP" | awk '{print $1}')"
    if [[ "$actual" != "$ASSET_SHA256" ]]; then
      echo "error: BuildKit asset zip SHA256 mismatch" >&2
      exit 1
    fi
  fi
  unzip -q "$ASSET_ZIP" -d "$TMP_DIR/unzipped"
  manifest_path="$(find "$TMP_DIR/unzipped" -maxdepth 2 -name manifest.json -print -quit)"
  if [[ -z "$manifest_path" ]]; then
    echo "error: BuildKit asset zip does not contain manifest.json" >&2
    exit 1
  fi
  ASSET_DIR="$(dirname "$manifest_path")"
fi

if [[ -z "$ASSET_DIR" ]]; then
  echo "==> No private BuildKit assets configured; keeping public placeholder."
  exit 0
fi

if [[ ! -f "$ASSET_DIR/manifest.json" ]]; then
  echo "error: private BuildKit asset directory must contain manifest.json: $ASSET_DIR" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$ASSET_DIR" "$DEST"
"$ROOT_DIR/tools/scripts/verify-nyxian-buildkit-assets.sh" "$DEST"
echo "==> Private BuildKit assets prepared at $DEST"
