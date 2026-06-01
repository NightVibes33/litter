#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${EMEXDE_CORECOMPILER_RELEASE_TAG:-emexde-corecompiler}"
REPO="${GITHUB_REPOSITORY:-NightVibes33/litter}"
ROOT="${ROOT:-$(pwd)}"
DEST="${EMEXDE_CORECOMPILER_PREBUILT_DIR:-$ROOT/ThirdParty/EmexDE/Prebuilt}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$DEST"
rm -rf "$DEST/CoreCompiler.framework" "$DEST/CoreCompilerSupportLibs"

gh release download "$RELEASE_TAG" \
  --repo "$REPO" \
  --pattern 'CoreCompiler.framework.tar.xz' \
  --pattern 'CoreCompilerSupportLibs.tar.xz' \
  --dir "$TMP_DIR" \
  --clobber

tar -xJf "$TMP_DIR/CoreCompiler.framework.tar.xz" -C "$DEST"
tar -xJf "$TMP_DIR/CoreCompilerSupportLibs.tar.xz" -C "$DEST"

CORE="$DEST/CoreCompiler.framework/CoreCompiler"
SUPPORT="$DEST/CoreCompilerSupportLibs"
if [ ! -f "$CORE" ]; then
  echo "error: missing CoreCompiler executable at $CORE" >&2
  exit 1
fi
if ! find "$SUPPORT" -maxdepth 1 -type f -name 'lib_Compiler*.dylib' -print -quit | grep -q .; then
  echo "error: missing CoreCompiler support dylibs in $SUPPORT" >&2
  exit 1
fi

normalize_binary() {
  binary="$1"
  if command -v install_name_tool >/dev/null 2>&1; then
    base="$(basename "$binary")"
    case "$binary" in
      */CoreCompiler.framework/CoreCompiler)
        install_name_tool -id '@rpath/CoreCompiler.framework/CoreCompiler' "$binary" 2>/dev/null || true
        install_name_tool -add_rpath '@loader_path/..' "$binary" 2>/dev/null || true
        ;;
      *.dylib)
        install_name_tool -id "@rpath/$base" "$binary" 2>/dev/null || true
        install_name_tool -add_rpath '@loader_path' "$binary" 2>/dev/null || true
        ;;
    esac
    if command -v otool >/dev/null 2>&1; then
      otool -L "$binary" | awk 'NR > 1 { print $1 }' | while IFS= read -r dependency; do
        dep_base="$(basename "$dependency")"
        case "$dep_base" in
          lib_Compiler*.dylib|libLLVM*.dylib|libllvm*.dylib)
            [ "$dependency" = "@rpath/$dep_base" ] || install_name_tool -change "$dependency" "@rpath/$dep_base" "$binary" 2>/dev/null || true
            ;;
        esac
      done
    fi
  fi
}

normalize_binary "$CORE"
find "$SUPPORT" -maxdepth 1 -type f -name '*.dylib' -print | while IFS= read -r dylib; do
  normalize_binary "$dylib"
done

echo "Prepared emexDE CoreCompiler artifacts in $DEST"
