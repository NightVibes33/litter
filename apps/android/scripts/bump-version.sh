#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_GRADLE="$SCRIPT_DIR/../app/build.gradle.kts"
VERSION_CODE_OVERRIDE="${LITTER_VERSION_CODE_OVERRIDE:-}"

# Read current versionCode
CURRENT=$(grep 'versionCode = ' "$BUILD_GRADLE" | head -1 | sed 's/[^0-9]//g')
if [[ -z "$CURRENT" ]]; then
    echo "ERROR: could not find versionCode in $BUILD_GRADLE" >&2
    exit 1
fi

if [[ -n "$VERSION_CODE_OVERRIDE" ]]; then
    if ! [[ "$VERSION_CODE_OVERRIDE" =~ ^[0-9]+$ ]]; then
        echo "ERROR: LITTER_VERSION_CODE_OVERRIDE must be numeric" >&2
        exit 1
    fi
    NEXT="$VERSION_CODE_OVERRIDE"
else
    NEXT=$((CURRENT + 1))
fi

# Update versionCode
perl -0pi -e "s/versionCode = $CURRENT/versionCode = $NEXT/" "$BUILD_GRADLE"

if [[ "$CURRENT" == "$NEXT" ]]; then
    echo "==> versionCode unchanged at $CURRENT"
else
    echo "==> Bumped versionCode: $CURRENT -> $NEXT"
fi
