#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative"
NYXIAN_ROOT="${NYXIAN_ROOT:-$ROOT_DIR/ThirdParty/Nyxian}"
FEATHER_ZSIGN_ROOT="${FEATHER_ZSIGN_ROOT:-$ROOT_DIR/ThirdParty/Feather/Zsign-Package/src}"
OUT_DIR="${LITTER_BUILDKIT_NATIVE_OUT_DIR:-$ROOT_DIR/artifacts/buildkit/LitterBuildKitNative.framework}"
MIN_IOS="${LITTER_BUILDKIT_MIN_IOS:-18.0}"
SDK="${IPHONEOS_SDK_PATH:-}"
MODE="${LITTER_BUILDKIT_NATIVE_MODE:-runner}"
CORECOMPILER_FRAMEWORK="${CORECOMPILER_FRAMEWORK:-}"
KITTYSTORE_SIGNER="${LITTER_BUILDKIT_ENABLE_KITTYSTORE_SIGNER:-1}"
OPENSSL_FRAMEWORK="${LITTER_BUILDKIT_OPENSSL_FRAMEWORK:-$NYXIAN_ROOT/Nyxian/LindChain/OpenSSL.xcframework/ios-arm64/OpenSSL.framework}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: build-litter-buildkit-native.sh must run on macOS with Xcode available" >&2
  exit 1
fi

if [[ -z "$SDK" ]]; then
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
fi

CXX="$(xcrun --sdk iphoneos --find clang++)"
CC="$(xcrun --sdk iphoneos --find clang)"
PLISTBUDDY="/usr/libexec/PlistBuddy"
BINARY_NAME="LitterBuildKitNative"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
MDK_HEADER_ROOT="$TMP_DIR/MobileDevelopmentKit"
CORECOMPILER_HEADER_ROOT="$TMP_DIR/CoreCompiler"
OPENSSL_LOWER_HEADER_ROOT="$TMP_DIR/OpenSSLHeaders"
OBJECT_DIR="$TMP_DIR/Objects"
mkdir -p "$OBJECT_DIR"

SOURCES=("$SRC_DIR/LitterBuildKitNative.mm")
COMMON_COMPILE_FLAGS=(
  -target "arm64-apple-ios$MIN_IOS"
  -isysroot "$SDK"
  -miphoneos-version-min="$MIN_IOS"
  -fmodules
  -fblocks
  -I"$SRC_DIR"
)
OBJC_COMPILE_FLAGS=(
  -fobjc-arc
)
CXX_COMPILE_FLAGS=(
  -std=c++17
)
LINK_FLAGS=(
  -target "arm64-apple-ios$MIN_IOS"
  -isysroot "$SDK"
  -miphoneos-version-min="$MIN_IOS"
  -dynamiclib
  -install_name "@rpath/LitterBuildKitNative.framework/LitterBuildKitNative"
  -Wl,-headerpad_max_install_names
  -Wl,-rpath,@loader_path/..
  -Wl,-rpath,@loader_path/../CoreCompilerSupportLibs
  -Wl,-rpath,@executable_path/Frameworks
  -framework Foundation
  -lz
)

if [[ "$MODE" = "inprocess" ]]; then
  if [[ -z "$CORECOMPILER_FRAMEWORK" || ! -d "$CORECOMPILER_FRAMEWORK" ]]; then
    echo "error: LITTER_BUILDKIT_NATIVE_MODE=inprocess requires CORECOMPILER_FRAMEWORK=/path/CoreCompiler.framework" >&2
    exit 1
  fi
  mkdir -p "$MDK_HEADER_ROOT" "$CORECOMPILER_HEADER_ROOT"
  find "$NYXIAN_ROOT/MobileDevelopmentKit" -type f -name '*.h' -exec cp {} "$MDK_HEADER_ROOT/" \;
  find "$NYXIAN_ROOT/CoreCompiler" -type f -name '*.h' -exec cp {} "$CORECOMPILER_HEADER_ROOT/" \;
  COMMON_COMPILE_FLAGS+=(
    -DLBN_ENABLE_INPROCESS=1
    -F"$(dirname "$CORECOMPILER_FRAMEWORK")"
    -I"$TMP_DIR"
    -I"$NYXIAN_ROOT"
    -I"$NYXIAN_ROOT/CoreCompiler"
    -I"$NYXIAN_ROOT/CoreCompiler/Support"
    -I"$NYXIAN_ROOT/MobileDevelopmentKit"
    -I"$NYXIAN_ROOT/MobileDevelopmentKit/Support"
  )
  LINK_FLAGS+=(
    -F"$(dirname "$CORECOMPILER_FRAMEWORK")"
    -framework CoreCompiler
  )
  SOURCES+=(
    "$SRC_DIR/LitterBuildKitInProcess.mm"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Support/MDKCFType.m"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Support/MDKDiagnostic.m"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Support/MDKFile.m"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Support/MDKFileSourceLocation.m"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Support/MDKJob.m"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Tools/MDKDriver.m"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Tools/MDKSDK.m"
    "$NYXIAN_ROOT/MobileDevelopmentKit/Tools/Linker/MDKLinker.m"
  )

  if [[ "$KITTYSTORE_SIGNER" != "0" ]]; then
    if [[ ! -d "$FEATHER_ZSIGN_ROOT" ]]; then
      echo "error: KittyStore signer requested but Feather Zsign source is missing: $FEATHER_ZSIGN_ROOT" >&2
      exit 1
    fi
    if [[ ! -d "$OPENSSL_FRAMEWORK" ]]; then
      echo "error: KittyStore signer requested but OpenSSL.framework is missing: $OPENSSL_FRAMEWORK" >&2
      exit 1
    fi
    mkdir -p "$OPENSSL_LOWER_HEADER_ROOT/openssl"
    find "$OPENSSL_FRAMEWORK/Headers" -type f -name '*.h' -exec ln -sf {} "$OPENSSL_LOWER_HEADER_ROOT/openssl/" \;
    COMMON_COMPILE_FLAGS+=(
      -DLBN_ENABLE_KITTYSTORE_SIGNER=1
      -I"$FEATHER_ZSIGN_ROOT"
      -I"$FEATHER_ZSIGN_ROOT/common"
      -I"$FEATHER_ZSIGN_ROOT/third-party/minizip"
      -I"$OPENSSL_LOWER_HEADER_ROOT"
      -F"$(dirname "$OPENSSL_FRAMEWORK")"
    )
    LINK_FLAGS+=(
      -F"$(dirname "$OPENSSL_FRAMEWORK")"
      -framework OpenSSL
    )
    SOURCES+=(
      "$FEATHER_ZSIGN_ROOT/archo.cpp"
      "$FEATHER_ZSIGN_ROOT/bundle.cpp"
      "$FEATHER_ZSIGN_ROOT/macho.cpp"
      "$FEATHER_ZSIGN_ROOT/openssl.cpp"
      "$FEATHER_ZSIGN_ROOT/signing.cpp"
      "$FEATHER_ZSIGN_ROOT/common/archive.cpp"
      "$FEATHER_ZSIGN_ROOT/common/base64.cpp"
      "$FEATHER_ZSIGN_ROOT/common/fs.cpp"
      "$FEATHER_ZSIGN_ROOT/common/json.cpp"
      "$FEATHER_ZSIGN_ROOT/common/log.cpp"
      "$FEATHER_ZSIGN_ROOT/common/sha.cpp"
      "$FEATHER_ZSIGN_ROOT/common/timer.cpp"
      "$FEATHER_ZSIGN_ROOT/common/util.cpp"
      "$FEATHER_ZSIGN_ROOT/third-party/minizip/ioapi.c"
      "$FEATHER_ZSIGN_ROOT/third-party/minizip/unzip.c"
      "$FEATHER_ZSIGN_ROOT/third-party/minizip/zip.c"
    )
  fi
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Headers" "$OUT_DIR/Modules"
cp "$SRC_DIR/LitterBuildKitNative.h" "$OUT_DIR/Headers/LitterBuildKitNative.h"

OBJECTS=()
index=0
for source in "${SOURCES[@]}"; do
  index=$((index + 1))
  ext="${source##*.}"
  object="$OBJECT_DIR/$(printf '%03d' "$index")-$(basename "$source").o"
  case "$ext" in
    c)
      "$CC" "${COMMON_COMPILE_FLAGS[@]}" -c "$source" -o "$object"
      ;;
    m)
      "$CC" "${COMMON_COMPILE_FLAGS[@]}" "${OBJC_COMPILE_FLAGS[@]}" -c "$source" -o "$object"
      ;;
    mm)
      "$CXX" "${COMMON_COMPILE_FLAGS[@]}" "${OBJC_COMPILE_FLAGS[@]}" "${CXX_COMPILE_FLAGS[@]}" -c "$source" -o "$object"
      ;;
    cpp|cc|cxx)
      "$CXX" "${COMMON_COMPILE_FLAGS[@]}" "${CXX_COMPILE_FLAGS[@]}" -c "$source" -o "$object"
      ;;
    *)
      echo "error: unsupported native source extension: $source" >&2
      exit 1
      ;;
  esac
  OBJECTS+=("$object")
done

"$CXX" "${LINK_FLAGS[@]}" "${OBJECTS[@]}" -o "$OUT_DIR/$BINARY_NAME"

cat > "$OUT_DIR/Modules/module.modulemap" <<'EOF_MODULE'
framework module LitterBuildKitNative {
  umbrella header "LitterBuildKitNative.h"
  export *
  module * { export * }
}
EOF_MODULE

cat > "$OUT_DIR/Info.plist" <<EOF_PLIST
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
  <key>LitterBuildKitNativeMode</key><string>$MODE</string>
</dict>
</plist>
EOF_PLIST

if [[ -x "$PLISTBUDDY" ]]; then
  "$PLISTBUDDY" -c 'Print :CFBundleExecutable' "$OUT_DIR/Info.plist" >/dev/null
fi

/usr/bin/lipo -info "$OUT_DIR/$BINARY_NAME"
echo "Built $OUT_DIR ($MODE mode)"
