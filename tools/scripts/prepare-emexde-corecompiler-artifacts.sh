#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(pwd)}"
NYXIAN_ROOT="$ROOT/ThirdParty/EmexDE/Source"
LLVM_ROOT="$NYXIAN_ROOT/LLVM-On-iOS"
DEST="$NYXIAN_ROOT/Frameworks/CoreCompiler/CoreCompilerSupportLibs"
LOCK="$ROOT/ThirdParty/EmexDE/UPSTREAM_LOCK.json"

if [ ! -f "$LOCK" ]; then
  echo "error: missing emexDE upstream lock: $LOCK" >&2
  exit 1
fi
if [ ! -d "$LLVM_ROOT" ] || [ ! -f "$LLVM_ROOT/Makefile" ]; then
  echo "error: LLVM-On-iOS submodule is not initialized: $LLVM_ROOT" >&2
  exit 1
fi

expected_llvm="$(python3 - "$LOCK" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))["llvmOnIOS"]["commit"])
PY
)"
expected_swift="$(python3 - "$LOCK" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))["llvmOnIOS"]["swiftBranch"])
PY
)"
actual_llvm="$(git -C "$LLVM_ROOT" rev-parse HEAD)"
actual_swift="$(sed -n 's/^SWIFT_BRANCH ?= //p' "$LLVM_ROOT/Makefile" | head -n 1)"

if [ "$actual_llvm" != "$expected_llvm" ]; then
  echo "error: LLVM-On-iOS checkout mismatch: expected $expected_llvm, got $actual_llvm" >&2
  exit 1
fi
if [ "$actual_swift" != "$expected_swift" ]; then
  echo "error: Swift toolchain branch mismatch: expected $expected_swift, got $actual_swift" >&2
  exit 1
fi

echo "Building exact upstream LLVM/Clang/Swift support from LLVM-On-iOS@$actual_llvm ($actual_swift)"
make -C "$LLVM_ROOT" LLVM.xcframework

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$LLVM_ROOT/CoreCompilerSupportLibs/." "$DEST/"
cp -R "$LLVM_ROOT/LLVM.xcframework" "$DEST/LLVM.xcframework"

LLVM_SLICE="$DEST/LLVM.xcframework/ios-arm64"
HEADERS="$LLVM_SLICE/Headers"
required=(
  "$LLVM_SLICE/llvm.a"
  "$HEADERS/llvm/Target/TargetOptions.h"
  "$HEADERS/llvm/MC/MCTargetOptions.h"
  "$HEADERS/clang/Driver/ToolChain.h"
  "$HEADERS/swift/Basic/InitializeSwiftModules.h"
  "$HEADERS/swift/FrontendTool/FrontendTool.h"
)
for path in "${required[@]}"; do
  if [ ! -s "$path" ]; then
    echo "error: exact upstream toolchain artifact is missing: $path" >&2
    exit 1
  fi
done

required_dylibs=(
  lib_CompilerSwiftBasicFormat.dylib
  lib_CompilerSwiftCompilerPluginMessageHandling.dylib
  lib_CompilerSwiftDiagnostics.dylib
  lib_CompilerSwiftIDEUtils.dylib
  lib_CompilerSwiftIfConfig.dylib
  lib_CompilerSwiftLexicalLookup.dylib
  lib_CompilerSwiftOperators.dylib
  lib_CompilerSwiftParser.dylib
  lib_CompilerSwiftParserDiagnostics.dylib
  lib_CompilerSwiftSyntax.dylib
  lib_CompilerSwiftSyntaxBuilder.dylib
  lib_CompilerSwiftSyntaxMacroExpansion.dylib
  lib_CompilerSwiftSyntaxMacros.dylib
  lib_CompilerSwiftWarningControl.dylib
)
for dylib in "${required_dylibs[@]}"; do
  if [ ! -s "$DEST/$dylib" ]; then
    echo "error: exact upstream CoreCompiler support dylib is missing: $dylib" >&2
    exit 1
  fi
done

smoke="$(mktemp -t emexde-llvm-smoke).cpp"
trap 'rm -f "$smoke"' EXIT
cat > "$smoke" <<'CPP'
#include <llvm/Target/TargetOptions.h>
#include <clang/Driver/ToolChain.h>
int main() {
  llvm::TargetOptions options;
  (void)options;
  return 0;
}
CPP
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang++ -std=c++20 -fsyntax-only -isysroot "$SDKROOT" -I"$HEADERS" "$smoke"

python3 - "$DEST/.litter-upstream-lock.json" "$expected_llvm" "$expected_swift" <<'PY'
import json,sys
path,llvm_sha,swift_branch=sys.argv[1:]
with open(path,"w") as f:
    json.dump({"llvmOnIOS":llvm_sha,"swiftBranch":swift_branch},f,indent=2,sort_keys=True)
    f.write("\n")
PY

find "$DEST" -maxdepth 1 -type f -name '*.dylib' -print | while IFS= read -r dylib; do
  base="$(basename "$dylib")"
  install_name_tool -id "@rpath/$base" "$dylib" 2>/dev/null || true
  install_name_tool -add_rpath '@loader_path' "$dylib" 2>/dev/null || true
done

echo "Prepared exact upstream emexDE CoreCompiler artifacts from LLVM-On-iOS@$actual_llvm"
