#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative"
OUT_DIR="${LITTER_BUILDKIT_NATIVE_OUT_DIR:-$ROOT_DIR/artifacts/buildkit/LitterBuildKitNative.framework}"
MIN_IOS="${LITTER_BUILDKIT_MIN_IOS:-18.0}"
SDK="${IPHONEOS_SDK_PATH:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: build-litter-buildkit-native.sh must run on macOS with Xcode available" >&2
  exit 1
fi

if [[ -z "$SDK" ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
fi

CLANG="$(xcrun --sdk iphoneos --find clang++)"
PLISTBUDDY="/usr/libexec/PlistBuddy"
BINARY_NAME="LitterBuildKitNative"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Headers" "$OUT_DIR/Modules"
cp "$SRC_DIR/LitterBuildKitNative.h" "$OUT_DIR/Headers/LitterBuildKitNative.h"

"$CLANG" \
  -target arm64-apple-ios"$MIN_IOS" \
  -isysroot "$SDK" \
  -miphoneos-version-min="$MIN_IOS" \
  -fobjc-arc \
  -fmodules \
  -dynamiclib \
  -install_name "@rpath/LitterBuildKitNative.framework/LitterBuildKitNative" \
  -framework Foundation \
  -I"$SRC_DIR" \
  "$SRC_DIR/LitterBuildKitNative.mm" \
  -o "$OUT_DIR/$BINARY_NAME"

cat > "$OUT_DIR/Modules/module.modulemap" <<'EOF'
framework module LitterBuildKitNative {
  umbrella header "LitterBuildKitNative.h"
  export *
  module * { export * }
}
EOF

cat > "$OUT_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$BINARY_NAME</string>
  <key>CFBundleIdentifier</key><string>com.sigkitten.litter.buildkit.native</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$BINARY_NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict>
</plist>
EOF

if [[ -x "$PLISTBUDDY" ]]; then
  "$PLISTBUDDY" -c 'Print :CFBundleExecutable' "$OUT_DIR/Info.plist" >/dev/null
fi

/usr/bin/lipo -info "$OUT_DIR/$BINARY_NAME"
echo "Built $OUT_DIR"
