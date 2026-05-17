#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
NYXIAN_ROOT="${NYXIAN_ROOT:-$ROOT_DIR/ThirdParty/Nyxian}"

missing=0
require_path() {
  label="$1"
  path="$2"
  rel="${path#$ROOT_DIR/}"
  if [ ! -e "$path" ] && ! git -C "$ROOT_DIR" cat-file -e "HEAD:$rel" 2>/dev/null; then
    echo "error: missing $label: $rel" >&2
    missing=1
  fi
}

require_path "Nyxian import manifest" "$NYXIAN_ROOT/LITTER_NYXIAN_IMPORT.json"
require_path "Nyxian license" "$NYXIAN_ROOT/LICENSE"
require_path "Nyxian submodule metadata" "$NYXIAN_ROOT/.gitmodules"
require_path "Nyxian Makefile" "$NYXIAN_ROOT/Makefile"
require_path "Nyxian Xcode project" "$NYXIAN_ROOT/Nyxian.xcodeproj/project.pbxproj"
require_path "CoreCompiler source" "$NYXIAN_ROOT/CoreCompiler/CoreCompiler.h"
require_path "CoreCompiler Swift compiler wrapper" "$NYXIAN_ROOT/CoreCompiler/Tools/Compiler/CCSwiftCompiler.cpp"
require_path "MobileDevelopmentKit source" "$NYXIAN_ROOT/MobileDevelopmentKit/MobileDevelopmentKit.h"
require_path "Shared Swift UIKit template" "$NYXIAN_ROOT/Shared/Templates/Application/Swift/UIKit/AppDelegate.swift"
require_path "LiveProcess source" "$NYXIAN_ROOT/LiveProcess/main.m"
require_path "LindChain source" "$NYXIAN_ROOT/Nyxian/LindChain/Core/Builder.swift"
require_path "ZSign source" "$NYXIAN_ROOT/Nyxian/LindChain/LiveContainer/ZSign/zsign.mm"
require_path "Nyxian OpenSSL xcframework" "$NYXIAN_ROOT/Nyxian/LindChain/OpenSSL.xcframework/Info.plist"
require_path "Nyxian OpenSSL framework binary" "$NYXIAN_ROOT/Nyxian/LindChain/OpenSSL.xcframework/ios-arm64/OpenSSL.framework/OpenSSL"
require_path "nxtool source" "$NYXIAN_ROOT/nxtool/main.m"
require_path "Litter native BuildKit bridge" "$NYXIAN_ROOT/LitterBuildKitNative/LitterBuildKitNative.h"
require_path "Litter in-process BuildKit bridge" "$NYXIAN_ROOT/LitterBuildKitNative/LitterBuildKitInProcess.mm"

if find "$NYXIAN_ROOT" -path '*/.git' -type d -print -quit | grep -q .; then
  echo "error: vendored Nyxian tree contains nested .git directories" >&2
  missing=1
fi
unexpected_framework="$(find "$NYXIAN_ROOT" -type d \( -name '*.framework' -o -name '*.xcframework' \) \
  ! -path "$NYXIAN_ROOT/Nyxian/LindChain/OpenSSL.xcframework" \
  ! -path "$NYXIAN_ROOT/Nyxian/LindChain/OpenSSL.xcframework/*" \
  -print -quit)"
if [ -n "$unexpected_framework" ]; then
  echo "error: vendored Nyxian source contains unexpected compiled framework directory: ${unexpected_framework#$ROOT_DIR/}" >&2
  missing=1
fi
if find "$NYXIAN_ROOT" -type f \( -name '*.ipa' -o -name '*.mobileprovision' -o -name '*.p12' -o -name '*.cer' \) -print -quit | grep -q .; then
  echo "error: vendored Nyxian source contains package/signing artifacts" >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

commit="$(python3 - "$NYXIAN_ROOT/LITTER_NYXIAN_IMPORT.json" <<'PYCOMMIT'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    print(json.load(fh).get('commit', 'unknown'))
PYCOMMIT
)"
echo "Nyxian source import verified: $commit"
