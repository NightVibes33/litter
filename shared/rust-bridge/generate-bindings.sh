#!/usr/bin/env bash
#
# Generate Swift bindings from codex-mobile-client.
#
# Usage:  ./generate-bindings.sh [--release] [--swift-only]
#
# Outputs:
#   generated/swift/   - Swift source files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR"
source "$WORKSPACE_DIR/../../tools/scripts/load-sccache-aws-creds.sh"
CRATE_DIR="$WORKSPACE_DIR/codex-mobile-client"
OUT_SWIFT="$WORKSPACE_DIR/generated/swift"

cd "$WORKSPACE_DIR"

if [[ -z "${RUSTC_WRAPPER:-}" ]] && [[ "${CARGO_INCREMENTAL:-}" != "1" ]] && command -v sccache >/dev/null 2>&1; then
    export RUSTC_WRAPPER="$(command -v sccache)"
fi

"$WORKSPACE_DIR/../../tools/scripts/update-alleycat-main.sh" --shared

PROFILE="debug"
for arg in "$@"; do
    case "$arg" in
        --release)
            PROFILE="release"
            ;;
        --swift-only)
            # Kept for compatibility with Makefile callers; Swift is the only
            # supported binding target in this iOS-only tree.
            ;;
        *)
            echo "usage: $(basename "$0") [--release] [--swift-only]" >&2
            exit 1
            ;;
    esac
done

# Build the cdylib so uniffi-bindgen can read its metadata.
echo "==> Building codex-mobile-client cdylib ($PROFILE)..."

if [[ "$PROFILE" == "release" ]]; then
    cargo build -p codex-mobile-client --release
else
    cargo build -p codex-mobile-client
fi

DYLIB_PATH="${CARGO_TARGET_DIR:-$WORKSPACE_DIR/target}/$PROFILE"

if [[ "$(uname)" == "Darwin" ]]; then
    DYLIB_FILE="$DYLIB_PATH/libcodex_mobile_client.dylib"
else
    DYLIB_FILE="$DYLIB_PATH/libcodex_mobile_client.so"
fi

if [[ ! -f "$DYLIB_FILE" ]]; then
    echo "ERROR: Could not find built library at $DYLIB_FILE" >&2
    exit 1
fi

echo "==> Generating Swift bindings -> $OUT_SWIFT"
mkdir -p "$OUT_SWIFT"
rm -f     "$OUT_SWIFT/codex_app_server_protocol.swift"     "$OUT_SWIFT/codex_app_server_protocolFFI.h"     "$OUT_SWIFT/codex_app_server_protocolFFI.modulemap"     "$OUT_SWIFT/codex_protocol.swift"     "$OUT_SWIFT/codex_protocolFFI.h"     "$OUT_SWIFT/codex_protocolFFI.modulemap"
cargo run -p uniffi-bindgen -- generate     --library "$DYLIB_FILE"     --language swift     --out-dir "$OUT_SWIFT"
cp "$OUT_SWIFT/codex_mobile_clientFFI.modulemap" "$OUT_SWIFT/module.modulemap"

echo "==> Done. Generated Swift bindings:"
find "$OUT_SWIFT" -type f | sort
