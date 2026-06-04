#!/usr/bin/env bash
# Download + extract the Alpine fakefs rootfs from a GitHub release of
# dnakov/litter-ish, pinned by version. The iSH kernel itself is now
# compiled from the `ish` Rust crate; only the rootfs tarball still ships
# as a prebuilt artifact.
#
# Usage:
#   ALPINE_FS_VERSION=v0.1.0 ./apps/ios/scripts/download-alpine-fs.sh
#
# Outputs:
#   apps/ios/Resources/fs.tar.gz          (bundled as Resource)
#   apps/ios/Resources/fs.version         (rootfs identity marker)

set -euo pipefail

VERSION="${ALPINE_FS_VERSION:-}"
if [[ -z "$VERSION" ]]; then
    echo "error: ALPINE_FS_VERSION must be set (e.g. v0.1.0)" >&2
    exit 1
fi

REPO="dnakov/litter-ish"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$IOS_DIR/Resources"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BASE_URL="https://github.com/$REPO/releases/download/$VERSION"
FAKEFS_TGZ="fs.tar.gz"
SUMS="SHA256SUMS"

fetch() {
    local name="$1"
    echo "==> Downloading $name"
    curl -fsSL --retry 3 -o "$TMP_DIR/$name" "$BASE_URL/$name"
}

fetch "$FAKEFS_TGZ"
fetch "$SUMS"

echo "==> Verifying checksum for $FAKEFS_TGZ"
( cd "$TMP_DIR" && grep " $FAKEFS_TGZ\$" "$SUMS" | shasum -a 256 -c - )

echo "==> Installing fs archive"
mkdir -p "$RESOURCES_DIR"
if [ -d "$RESOURCES_DIR/fs" ]; then
    staging="$RESOURCES_DIR/.fs.old-$$"
    if mv "$RESOURCES_DIR/fs" "$staging" 2>/dev/null; then
        rm -rf "$staging" || true
    else
        for _ in 1 2 3; do
            rm -rf "$RESOURCES_DIR/fs" && break
            sleep 1
        done
    fi
fi
cp "$TMP_DIR/$FAKEFS_TGZ" "$RESOURCES_DIR/fs.tar.gz"
printf 'alpine-fs=%s\n' "$VERSION" > "$RESOURCES_DIR/fs.version"

echo
echo "alpine-fs $VERSION archive installed:"
du -sh "$RESOURCES_DIR/fs.tar.gz"
