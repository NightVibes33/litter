#!/usr/bin/env bash
# Download Android arm64 CLI binaries for the on-device Codex agent.
#
# Deprecated: Android 16 KB page-size compatibility requires app native
# libraries to stay uncompressed and page-aligned in the APK. The old approach
# packaged CLI executables as `lib<tool>.so` only to force extraction into
# `nativeLibraryDir`; that extraction mode now triggers compatibility warnings
# on current Android builds, and the pinned wget binary is only 4 KB aligned.
#
# The old source was bnsmb/binaries-for-Android pinned by SHA. Keep this script
# as a no-op placeholder until Android gets a non-JNI delivery path for bundled
# CLI tools. Tools we don't bundle (`ls`, `cat`, `grep`, `sed`, `awk`, etc.)
# still resolve through `/system/bin` via PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEST="$REPO_DIR/apps/android/app/src/main/jniLibs/arm64-v8a"

PIN_SHA="728fde6d326ccc80b87b87305de919afd5891f37"
BASE_URL="https://raw.githubusercontent.com/bnsmb/binaries-for-Android/${PIN_SHA}/binaries"

# Format: <local-name>:<remote-name>:<sha256>
TOOLS=()

if [ "${#TOOLS[@]}" -eq 0 ]; then
    echo "==> Android bundled CLI tools are disabled for 16 KB page-size compatibility"
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required" >&2
    exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
    echo "error: sha256sum is required" >&2
    exit 1
fi

mkdir -p "$DEST"

for entry in "${TOOLS[@]}"; do
    IFS=':' read -r local_name remote_name expected_sha <<<"$entry"
    target="$DEST/$local_name"

    if [ -f "$target" ]; then
        actual_sha="$(sha256sum "$target" | awk '{print $1}')"
        if [ "$actual_sha" = "$expected_sha" ]; then
            echo "==> $local_name already present, skipping (sha256 ok)"
            continue
        fi
        echo "==> $local_name has mismatched sha256, re-downloading"
    fi

    echo "==> Downloading $local_name <- $remote_name"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    curl -fsSL "$BASE_URL/$remote_name" -o "$tmp"
    actual_sha="$(sha256sum "$tmp" | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
        echo "error: sha256 mismatch for $remote_name" >&2
        echo "  expected: $expected_sha" >&2
        echo "  actual:   $actual_sha" >&2
        rm -f "$tmp"
        exit 1
    fi
    chmod +x "$tmp"
    mv "$tmp" "$target"
    trap - EXIT
    echo "    placed at $target ($(stat -c '%s' "$target") bytes)"
done

echo "==> Android CLI tools ready in $DEST/"
