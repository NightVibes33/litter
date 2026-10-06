#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
LLVM_SOURCE="$ROOT/ThirdParty/EmexDE/Source/LLVM-On-iOS"
OUTPUT="${1:-$ROOT/build/nyxian-toolchain}"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  echo 'The pinned upstream Swift preset requires an Apple Silicon macOS host.' >&2
  exit 1
}
mkdir -p "$OUTPUT"
# Use the nested upstream Makefile and its preset: fetch matching sibling
# repositories, build the real Swift frontend, and bundle generated headers.
(cd "$LLVM_SOURCE" && make CHECK_DEPS=0 all)
[[ -s "$LLVM_SOURCE/LLVM.xcframework/ios-arm64/llvm.a" ]]
[[ -s "$LLVM_SOURCE/LLVM.xcframework/ios-arm64/Headers/swift/Config.h" ]]
[[ -s "$LLVM_SOURCE/LLVM.xcframework/ios-arm64/Headers/swift/Option/Options.inc" ]]
find "$LLVM_SOURCE/CoreCompilerSupportLibs" -maxdepth 1 -name 'lib_Compiler*.dylib' -print -quit | grep -q .
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/CoreCompilerSupportLibs"
cp -R "$LLVM_SOURCE/CoreCompilerSupportLibs/." "$STAGING/CoreCompilerSupportLibs/"
# The support bundle may contain an older LLVM framework with real header
# directories. Replace it before copying the freshly built framework: merging
# a directory symlink over that directory fails with Darwin cp.
rm -rf "$STAGING/CoreCompilerSupportLibs/LLVM.xcframework"
cp -RL "$LLVM_SOURCE/LLVM.xcframework" "$STAGING/CoreCompilerSupportLibs/"
HEADERS="$STAGING/CoreCompilerSupportLibs/LLVM.xcframework/ios-arm64/Headers"
BUILD_ROOT="$LLVM_SOURCE/build/LLVMClangSwift_iphoneos"
# Include every generated header from this same build, after the upstream
# source-header copies. No headers are downloaded from a different release.
# Swift's generated include tree links swift/bridging back to its source
# headers. Follow those links so they merge with the framework's directories
# and the packaged headers do not depend on the CI checkout remaining present.
for generated in \
  "$BUILD_ROOT/llvm-iphoneos-arm64/include" \
  "$BUILD_ROOT/llvm-iphoneos-arm64/tools/clang/include" \
  "$BUILD_ROOT/llvm-iphoneos-arm64/tools/lld/include" \
  "$BUILD_ROOT/swift-iphoneos-arm64/include"; do
  if [ -d "$generated" ]; then cp -RL "$generated/." "$HEADERS/"; fi
done
cat > "$STAGING/compiler-headers.cpp" <<'CPP'
#include <swift/Frontend/Frontend.h>
#include <swift/FrontendTool/FrontendTool.h>
#include <clang/Tooling/DependencyScanning/DependencyScanningService.h>
#include <lld/Common/Driver.h>
#include <lld/Common/Version.h>
CPP
xcrun --sdk iphoneos clang++ -std=c++20 -target arm64-apple-ios18.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -I "$HEADERS" \
  -fsyntax-only "$STAGING/compiler-headers.cpp"
# The Swift source-root module map is not a standalone LLVM framework map.
# Xcode supplies the framework module; keep every compiler header unchanged.
rm -f "$STAGING/CoreCompilerSupportLibs/LLVM.xcframework/ios-arm64/Headers/module.modulemap"
tar -czf "$OUTPUT/compiler-support.tar.gz" -C "$STAGING" CoreCompilerSupportLibs
cp "$LLVM_SOURCE/SwiftToolchain.zip" "$OUTPUT/SwiftToolchain.zip"
python3 "$ROOT/tools/scripts/nyxian-toolchain-provenance.py" create "$OUTPUT"
