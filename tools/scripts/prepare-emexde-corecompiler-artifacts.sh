#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${EMEXDE_CORECOMPILER_RELEASE_TAG:-emexde-corecompiler}"
REPO="${GITHUB_REPOSITORY:-NightVibes33/litter}"
ROOT="${ROOT:-$(pwd)}"
CORECOMPILER_ROOT="$ROOT/ThirdParty/EmexDE/Source/CoreCompiler"
DEST="$CORECOMPILER_ROOT/CoreCompilerSupportLibs"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$CORECOMPILER_ROOT"
rm -rf "$DEST"

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer $GITHUB_TOKEN")
elif [ -n "${GH_TOKEN:-}" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer $GH_TOKEN")
fi

RELEASE_JSON="$TMP_DIR/release.json"
curl -fL --retry 3 --retry-delay 5 --max-time 120 \
  "${AUTH_HEADER[@]}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG" \
  -o "$RELEASE_JSON"

python3 - "$RELEASE_JSON" "$TMP_DIR" <<'PY_INNER'
import json
import pathlib
import sys

release_json = pathlib.Path(sys.argv[1])
out_dir = pathlib.Path(sys.argv[2])
release = json.loads(release_json.read_text())
required = {"CoreCompilerSupportLibs.tar.xz", "LLVM.xcframework.tar.xz"}
assets = {asset.get("name"): asset for asset in release.get("assets", [])}
missing = sorted(required - set(assets))
if missing:
    raise SystemExit("missing release assets: " + ", ".join(missing))
for name in sorted(required):
    asset = assets[name]
    (out_dir / f"{name}.asset-url").write_text(asset["url"])
PY_INNER

for name in CoreCompilerSupportLibs.tar.xz LLVM.xcframework.tar.xz; do
  asset_url="$(cat "$TMP_DIR/$name.asset-url")"
  curl -fL --retry 3 --retry-delay 5 --max-time 300 \
    "${AUTH_HEADER[@]}" \
    -H "Accept: application/octet-stream" \
    "$asset_url" \
    -o "$TMP_DIR/$name"
done

tar -xJf "$TMP_DIR/CoreCompilerSupportLibs.tar.xz" -C "$CORECOMPILER_ROOT"
tar -xJf "$TMP_DIR/LLVM.xcframework.tar.xz" -C "$DEST"

SUPPORT="$DEST"
LLVM_ROOT="$DEST/LLVM.xcframework/ios-arm64"
if ! find "$SUPPORT" -maxdepth 1 -type f -name 'lib_Compiler*.dylib' -print -quit | grep -q .; then
  echo "error: missing CoreCompiler support dylibs in $SUPPORT" >&2
  exit 1
fi
if [ ! -f "$LLVM_ROOT/llvm.a" ]; then
  echo "error: missing LLVM static library at $LLVM_ROOT/llvm.a" >&2
  exit 1
fi
if [ ! -f "$LLVM_ROOT/Headers/llvm/Support/Threading.h" ]; then
  echo "error: missing LLVM headers in $LLVM_ROOT/Headers" >&2
  exit 1
fi

normalize_dylib() {
  dylib="$1"
  if command -v install_name_tool >/dev/null 2>&1; then
    base="$(basename "$dylib")"
    install_name_tool -id "@rpath/$base" "$dylib" 2>/dev/null || true
    install_name_tool -add_rpath '@loader_path' "$dylib" 2>/dev/null || true
    if command -v otool >/dev/null 2>&1; then
      otool -L "$dylib" | awk 'NR > 1 { print $1 }' | while IFS= read -r dependency; do
        dep_base="$(basename "$dependency")"
        case "$dep_base" in
          lib_Compiler*.dylib|libLLVM*.dylib|libllvm*.dylib)
            [ "$dependency" = "@rpath/$dep_base" ] || install_name_tool -change "$dependency" "@rpath/$dep_base" "$dylib" 2>/dev/null || true
            ;;
        esac
      done
    fi
  fi
}

find "$SUPPORT" -maxdepth 1 -type f -name '*.dylib' -print | while IFS= read -r dylib; do
  normalize_dylib "$dylib"
done

echo "Prepared emexDE CoreCompiler support artifacts in $DEST"
