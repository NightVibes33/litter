#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
FRAMEWORKS_DIR="$IOS_DIR/Frameworks"
LLAMA_VERSION="${LLAMA_CPP_VERSION:-b9070}"
LLAMA_ZIP="llama-${LLAMA_VERSION}-xcframework.zip"
LLAMA_URL="${LLAMA_CPP_XCFRAMEWORK_URL:-https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/${LLAMA_ZIP}}"
LLAMA_SHA256="${LLAMA_CPP_XCFRAMEWORK_SHA256:-7c9352dcab083c40cadaebfbb67a44c6500ca254d476ba83fb419d770425681f}"
CACHE_DIR="${LITTER_LLAMA_CACHE_DIR:-${HOME}/Library/Caches/litter-build/llama.cpp}"
ZIP_PATH="$CACHE_DIR/$LLAMA_ZIP"
DEST="$FRAMEWORKS_DIR/llama.xcframework"
TMP_DIR="$CACHE_DIR/extract-$LLAMA_VERSION-$$"

if [ -d "$DEST" ]; then
  echo "==> llama.cpp XCFramework already exists: $DEST"
  exit 0
fi

mkdir -p "$FRAMEWORKS_DIR" "$CACHE_DIR"

if [ ! -f "$ZIP_PATH" ]; then
  echo "==> Downloading llama.cpp $LLAMA_VERSION XCFramework..."
  curl --fail --location --retry 3 --output "$ZIP_PATH" "$LLAMA_URL"
fi

ACTUAL_SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
if [ "$ACTUAL_SHA" != "$LLAMA_SHA256" ]; then
  echo "ERROR: llama.cpp XCFramework checksum mismatch" >&2
  echo "expected: $LLAMA_SHA256" >&2
  echo "actual:   $ACTUAL_SHA" >&2
  rm -f "$ZIP_PATH"
  exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
if command -v ditto >/dev/null 2>&1; then
  ditto -x -k "$ZIP_PATH" "$TMP_DIR"
elif command -v unzip >/dev/null 2>&1; then
  unzip -q "$ZIP_PATH" -d "$TMP_DIR"
else
  echo "ERROR: need ditto or unzip to extract $ZIP_PATH" >&2
  exit 1
fi

FOUND=$(find "$TMP_DIR" -maxdepth 3 -type d -name 'llama.xcframework' -print | head -n 1)
if [ -z "$FOUND" ]; then
  echo "ERROR: llama.xcframework not found in $ZIP_PATH" >&2
  find "$TMP_DIR" -maxdepth 3 -print >&2
  rm -rf "$TMP_DIR"
  exit 1
fi

rm -rf "$DEST"
mv "$FOUND" "$DEST"
rm -rf "$TMP_DIR"
echo "==> Installed $DEST"
