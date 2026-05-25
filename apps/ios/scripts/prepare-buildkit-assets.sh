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


refresh_native_driver_if_needed() {
  local asset_root="$1"
  local manifest="$asset_root/manifest.json"
  local expected actual mode core_rel native_rel openssl_rel source_commit

  expected="$($ROOT_DIR/tools/scripts/buildkit-native-source-fingerprint.sh 2>/dev/null || true)"
  if [[ -z "$expected" ]]; then
    return 0
  fi

  actual="$(python3 - "$manifest" <<'PY_ACTUAL'
import json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(manifest.get("nativeDriverSourceFingerprint") or (manifest.get("source") or {}).get("nativeDriverSourceFingerprint") or "")
PY_ACTUAL
)"
  if [[ "$actual" == "$expected" ]]; then
    return 0
  fi

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: private BuildKit native driver fingerprint mismatch" >&2
    echo "expected=$expected" >&2
    echo "actual=${actual:-missing}" >&2
    echo "Rebuild and upload the private BuildKit assets on macOS, or run this workflow on a macOS runner that can refresh LitterBuildKitNative.framework." >&2
    exit 1
  fi

  echo "==> Refreshing private LitterBuildKitNative.framework for current sources"
  echo "expected nativeDriverSourceFingerprint=$expected"
  echo "asset nativeDriverSourceFingerprint=${actual:-missing}"

  read -r mode core_rel native_rel openssl_rel < <(python3 - "$manifest" <<'PY_PATHS'
import json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
toolchain = manifest.get("toolchain") or {}
print(
    toolchain.get("nativeDriverMode") or "inprocess",
    toolchain.get("coreCompilerFramework") or "Toolchains/Nyxian/CoreCompiler.framework",
    toolchain.get("nativeDriverFramework") or "Toolchains/Nyxian/LitterBuildKitNative.framework",
    toolchain.get("opensslFramework") or "",
)
PY_PATHS
)

  if [[ "$mode" != "inprocess" ]]; then
    echo "error: cannot refresh private BuildKit native driver for mode '$mode'; expected inprocess" >&2
    exit 1
  fi

  local core_framework="$asset_root/$core_rel"
  local native_framework="$asset_root/$native_rel"
  local openssl_framework=""
  if [[ -n "$openssl_rel" ]]; then
    openssl_framework="$asset_root/$openssl_rel"
  fi
  if [[ ! -f "$core_framework/CoreCompiler" ]]; then
    echo "error: private BuildKit assets are missing CoreCompiler executable: $core_framework/CoreCompiler" >&2
    exit 1
  fi
  if [[ -n "$openssl_framework" && ! -d "$openssl_framework" ]]; then
    echo "error: manifest references missing OpenSSL framework: $openssl_framework" >&2
    exit 1
  fi

  LITTER_BUILDKIT_NATIVE_MODE="$mode" \
  CORECOMPILER_FRAMEWORK="$core_framework" \
  LITTER_BUILDKIT_NATIVE_OUT_DIR="$native_framework" \
  LITTER_BUILDKIT_OPENSSL_FRAMEWORK="$openssl_framework" \
  LITTER_BUILDKIT_ENABLE_KITTYSTORE_SIGNER=1 \
    "$ROOT_DIR/tools/scripts/build-litter-buildkit-native.sh"

  if [[ -f "$native_framework/LitterBuildKitNative" ]]; then
    /usr/bin/codesign --force --sign - "$native_framework/LitterBuildKitNative"
  fi

  source_commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
  python3 - "$asset_root" "$expected" "$source_commit" <<'PY_MANIFEST'
import datetime, hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
fingerprint = sys.argv[2]
source_commit = sys.argv[3] or None
manifest_path = root / "manifest.json"
manifest = json.loads(manifest_path.read_text())
manifest["createdAt"] = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
manifest["nativeDriverSourceFingerprint"] = fingerprint
source = manifest.setdefault("source", {})
source["nativeDriverSourceFingerprint"] = fingerprint
if source_commit:
    manifest["sourceCommit"] = source_commit
    source["repositoryCommit"] = source_commit
hashes = {}
for item in sorted(root.rglob("*")):
    if item == manifest_path or not item.is_file() or item.is_symlink():
        continue
    if item.stat().st_size > 64 * 1024 * 1024:
        continue
    rel = item.relative_to(root).as_posix()
    h = hashlib.sha256()
    with item.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    hashes[rel] = h.hexdigest()
manifest["sha256"] = hashes
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY_MANIFEST
}

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
refresh_native_driver_if_needed "$DEST"
"$ROOT_DIR/tools/scripts/verify-nyxian-buildkit-assets.sh" "$DEST"
echo "==> Private BuildKit assets prepared at $DEST"
