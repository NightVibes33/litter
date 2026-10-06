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
# Install the complete upstream runtime toolchain into the same Shared resource
# directory used by Nyxian's install-nyxian target and Alley Cat's resource phase.
SHARED="$ROOT/ThirdParty/EmexDE/Source/Shared"
rm -rf "$SHARED/SwiftToolchain"
unzip -q "$ARTIFACTS/SwiftToolchain.zip" -d "$SHARED"
[[ -f "$SHARED/SwiftToolchain/usr/bin/swiftc" ]]
[[ -f "$SHARED/SwiftToolchain/usr/bin/swift-frontend" ]]
echo 'Installed matching upstream compiler libraries, generated headers, and runtime toolchain.'
