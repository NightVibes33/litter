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
cp -R -L "$ASSET_DIR" "$DEST"

if [[ "${LITTER_BUILDKIT_REBUILD_NATIVE_DRIVER:-1}" != "0" ]]; then
  CORE_FRAMEWORK="$DEST/Toolchains/Nyxian/CoreCompiler.framework"
  REBUILT_DRIVER="$TMP_DIR/LitterBuildKitNative.framework"
  if [[ ! -d "$CORE_FRAMEWORK" ]]; then
    echo "error: cannot rebuild LitterBuildKitNative.framework because CoreCompiler.framework is missing: $CORE_FRAMEWORK" >&2
    exit 1
  fi
  echo "==> Rebuilding LitterBuildKitNative.framework from current repo source"
  LITTER_BUILDKIT_NATIVE_MODE="${LITTER_BUILDKIT_NATIVE_MODE:-inprocess}" \
    CORECOMPILER_FRAMEWORK="$CORE_FRAMEWORK" \
    LITTER_BUILDKIT_NATIVE_OUT_DIR="$REBUILT_DRIVER" \
    "$ROOT_DIR/tools/scripts/build-litter-buildkit-native.sh"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$REBUILT_DRIVER/LitterBuildKitNative"
  fi
  rm -rf "$DEST/Toolchains/Nyxian/LitterBuildKitNative.framework"
  cp -R "$REBUILT_DRIVER" "$DEST/Toolchains/Nyxian/LitterBuildKitNative.framework"
  python3 - "$DEST" <<'PYHASH'
import datetime
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest_path = root / "manifest.json"
manifest = json.loads(manifest_path.read_text())
sha = manifest.setdefault("sha256", {})
prefix = "Toolchains/Nyxian/LitterBuildKitNative.framework/"
for key in list(sha):
    if key.startswith(prefix):
        del sha[key]
framework_root = root / prefix
for path in sorted(framework_root.rglob("*")):
    if path.is_file() and path.stat().st_size <= 64 * 1024 * 1024:
        rel = path.relative_to(root).as_posix()
        h = hashlib.sha256()
        with path.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                h.update(chunk)
        sha[rel] = h.hexdigest()
manifest["createdAt"] = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
toolchain = manifest.setdefault("toolchain", {})
toolchain["nativeDriverMode"] = "inprocess"
capabilities = list(manifest.get("capabilities") or [])
if "in-process-native-driver" not in capabilities:
    capabilities.append("in-process-native-driver")
if "in-process-ipa-packager" not in capabilities:
    capabilities.append("in-process-ipa-packager")
manifest["capabilities"] = capabilities
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PYHASH
fi

"$ROOT_DIR/tools/scripts/verify-nyxian-buildkit-assets.sh" "$DEST"
echo "==> Private BuildKit assets prepared at $DEST"
