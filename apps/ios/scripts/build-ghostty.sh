#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/../.." && pwd)"
GHOSTTY_DIR="$REPO_DIR/shared/third_party/ghostty"
GENERATED_DIR="$IOS_DIR/GeneratedRust"
STAGING_DIR="${GHOSTTY_BUILD_DIR:-$GENERATED_DIR/ghostty-build}"
XCODE_DEVELOPER_DIR="${GHOSTTY_XCODE_DEVELOPER_DIR:-$(xcode-select -p)}"
CLT_DEVELOPER_DIR="${GHOSTTY_CLT_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

if [ ! -f "$GHOSTTY_DIR/build.zig" ]; then
    echo "error: Ghostty submodule is missing; run git submodule update --init --recursive shared/third_party/ghostty" >&2
    exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
    echo "error: zig is required to build Ghostty (brew install zig)" >&2
    exit 1
fi

# Apply Litter's mobile-embed patches if not already applied. Idempotent;
# safe to call on every build. Required when this script is invoked
# directly (CI, build-rust.sh fallback) without going through the
# Makefile's STAMP_SYNC_GHOSTTY dep chain.
"$REPO_DIR/apps/ios/scripts/sync-ghostty.sh" --preserve-current

if ! grep -q 'ghostty_surface_write' "$GHOSTTY_DIR/include/ghostty.h"; then
    echo "error: Ghostty header shape changed; expected external PTY ghostty_surface_write in include/ghostty.h" >&2
    exit 1
fi

if ! grep -q 'external_pty_write' "$GHOSTTY_DIR/include/ghostty.h"; then
    echo "error: Ghostty header shape changed; expected external_pty_write callback in include/ghostty.h" >&2
    exit 1
fi

if ! grep -q 'GHOSTTY_PLATFORM_IOS' "$GHOSTTY_DIR/include/ghostty.h"; then
    echo "error: vendored Ghostty does not expose the iOS platform surface" >&2
    exit 1
fi

ZIG_CACHE_DIR="${GHOSTTY_ZIG_CACHE_DIR:-$STAGING_DIR/zig-cache}"

mkdir -p "$GENERATED_DIR/Headers" "$GENERATED_DIR/ios-device" "$GENERATED_DIR/ios-sim" "$STAGING_DIR/bin"
rm -rf "$ZIG_CACHE_DIR"
mkdir -p "$ZIG_CACHE_DIR/global" "$ZIG_CACHE_DIR/local"

if [ ! -d "$XCODE_DEVELOPER_DIR/Platforms/iPhoneOS.platform" ]; then
    echo "error: Xcode developer dir does not contain iPhoneOS SDKs: $XCODE_DEVELOPER_DIR" >&2
    exit 1
fi

# Zig 0.15.2 can fail to link its macOS build runner against Xcode 26.4's
# arm64e-only macOS libSystem.tbd. Keep iOS SDK lookups on Xcode, but route
# host macOS SDK lookups through Command Line Tools when available.
cat > "$STAGING_DIR/bin/xcrun" <<EOF
#!/usr/bin/env bash
sdk=""
prev=""
for arg in "\$@"; do
    if [ "\$prev" = "--sdk" ]; then
        sdk="\$arg"
        break
    fi
    prev="\$arg"
done

case "\$sdk" in
    macosx)
        if [ -d "$CLT_DEVELOPER_DIR/SDKs/MacOSX.sdk" ]; then
            exec env DEVELOPER_DIR="$CLT_DEVELOPER_DIR" /usr/bin/xcrun "\$@"
        fi
        ;;
esac

exec env DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" /usr/bin/xcrun "\$@"
EOF
chmod +x "$STAGING_DIR/bin/xcrun"

build_slice() {
    local name="$1"
    local target="$2"
    local cpu="$3"
    local output="$4"
    local prefix="$STAGING_DIR/$name"
    local zig_args

    rm -rf "$prefix"
    mkdir -p "$prefix"

    echo "==> Building Ghostty iOS $name static library..."
    (
        cd "$GHOSTTY_DIR"
        zig_args=(zig build \
            -Dlitter-ios-static=true \
            -Dapp-runtime=none \
            -Drenderer=metal \
            -Dfont-backend=coretext \
            -Demit-exe=false \
            -Demit-lib-vt=false \
            -Demit-xcframework=false \
            -Demit-macos-app=false \
            -Demit-docs=false \
            -Demit-terminfo=false \
            -Demit-termcap=false \
            -Demit-themes=false \
            -Demit-webdata=false \
            -Di18n=false \
            -Dsentry=false \
            -Dtarget="$target")
        if [ -n "$cpu" ]; then
            zig_args+=(-Dcpu="$cpu")
        fi
        zig_args+=(\
            -Doptimize=ReleaseFast \
            --prefix "$prefix")
        env \
            PATH="$STAGING_DIR/bin:$PATH" \
            DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
            ZIG_GLOBAL_CACHE_DIR="$ZIG_CACHE_DIR/global" \
            ZIG_LOCAL_CACHE_DIR="$ZIG_CACHE_DIR/local" \
            "${zig_args[@]}"
    )

    if [ ! -f "$prefix/lib/ghostty-internal.a" ]; then
        echo "error: Ghostty $name build completed but $prefix/lib/ghostty-internal.a was not produced" >&2
        exit 1
    fi

    cp "$prefix/lib/ghostty-internal.a" "$output"
}

echo "==> Building Ghostty iOS static libraries from $(git -C "$GHOSTTY_DIR" rev-parse --short HEAD)..."
build_slice "ios-device" "aarch64-ios.18.0" "" "$GENERATED_DIR/ios-device/libghostty.a"
build_slice "ios-sim" "aarch64-ios.18.0-simulator" "apple_a17" "$GENERATED_DIR/ios-sim/libghostty.a"

cp "$GHOSTTY_DIR/include/ghostty.h" "$GENERATED_DIR/Headers/ghostty.h"

echo "==> Ghostty iOS artifacts installed:"
echo "    $GENERATED_DIR/Headers/ghostty.h"
echo "    $GENERATED_DIR/ios-device/libghostty.a"
echo "    $GENERATED_DIR/ios-sim/libghostty.a"
