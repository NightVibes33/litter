#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FRAMEWORKS_DIR="$IOS_DIR/Frameworks"
DEST="$FRAMEWORKS_DIR/llama.xcframework"

LLAMA_VERSION="${LLAMA_CPP_VERSION:-main}"
LLAMA_REPO="${LLAMA_CPP_REPO:-https://github.com/animehacker/llama-turboquant.git}"
LLAMA_SOURCE_FLAVOR="${LLAMA_CPP_FLAVOR:-turboquant}"
CACHE_DIR="${LITTER_LLAMA_CACHE_DIR:-${HOME}/Library/Caches/litter-build/llama.cpp}"
SOURCE_DIR="$CACHE_DIR/source-$LLAMA_SOURCE_FLAVOR-$LLAMA_VERSION"
BUILD_OUTPUT="$SOURCE_DIR/build-apple/llama.xcframework"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: llama.cpp iOS XCFramework must be built on a macOS runner with Xcode." >&2
  exit 1
fi

for tool in git cmake xcrun rsync; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool not found: $tool" >&2
    exit 1
  fi
done

mkdir -p "$FRAMEWORKS_DIR" "$CACHE_DIR"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  rm -rf "$SOURCE_DIR"
  echo "==> Cloning llama.cpp $LLAMA_SOURCE_FLAVOR from $LLAMA_REPO ($LLAMA_VERSION)..."
  git clone --depth 1 --branch "$LLAMA_VERSION" "$LLAMA_REPO" "$SOURCE_DIR"
else
  echo "==> Updating cached llama.cpp $LLAMA_SOURCE_FLAVOR source..."
  git -C "$SOURCE_DIR" remote set-url origin "$LLAMA_REPO"
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$LLAMA_VERSION"
  git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
fi

echo "==> Building llama.cpp Apple XCFramework from source..."
(
  cd "$SOURCE_DIR"
  bash ./build-xcframework.sh
)

if [[ ! -d "$BUILD_OUTPUT" ]]; then
  echo "ERROR: llama.cpp build did not produce $BUILD_OUTPUT" >&2
  exit 1
fi

rm -rf "$DEST"
rsync -a "$BUILD_OUTPUT/" "$DEST/"
RESOLVED_SHA="$(git -C "$SOURCE_DIR" rev-parse --short=12 HEAD)"
{
  echo "flavor=$LLAMA_SOURCE_FLAVOR"
  echo "repo=$LLAMA_REPO"
  echo "ref=$LLAMA_VERSION"
  echo "commit=$RESOLVED_SHA"
} > "$FRAMEWORKS_DIR/llama.version"
echo "==> Installed runner-built $DEST from $LLAMA_SOURCE_FLAVOR@$RESOLVED_SHA"
