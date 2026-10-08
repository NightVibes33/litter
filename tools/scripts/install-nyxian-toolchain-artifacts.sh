#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
ARTIFACTS="${1:?Provide the matching artifact directory}"
python3 "$ROOT/tools/scripts/nyxian-toolchain-provenance.py" verify "$ARTIFACTS"
CORE="$ROOT/ThirdParty/EmexDE/Source/Frameworks/CoreCompiler"
rm -rf "$CORE/CoreCompilerSupportLibs"
tar -xzf "$ARTIFACTS/compiler-support.tar.gz" -C "$CORE"
HEADERS="$CORE/CoreCompilerSupportLibs/LLVM.xcframework/ios-arm64/Headers"
for header in swift/Config.h swift/Option/Options.inc swift/Frontend/Frontend.h llvm/Config/llvm-config.h clang/Config/config.h; do
  [[ -s "$HEADERS/$header" ]] || { echo "Missing generated compiler header: $header" >&2; exit 1; }
done
[[ -s "$CORE/CoreCompilerSupportLibs/LLVM.xcframework/ios-arm64/llvm.a" ]]
# Nyxian executes its compiler in CoreCompiler.framework. Its Shared resources
# are the upstream compressed include/lib/swift archives, not standalone tools.
# SwiftToolchain.zip remains a provenance-checked CI artifact; never expand it
# into Shared, which is copied into the installed app.
SHARED="$ROOT/ThirdParty/EmexDE/Source/Shared"
rm -rf "$SHARED/SwiftToolchain"
for archive in include lib swift; do
  [[ -s "$SHARED/$archive.zip" ]] || { echo "Missing upstream $archive.zip" >&2; exit 1; }
done
echo 'Installed matching compiler libraries and headers; retained upstream compressed bootstrap resources.'
