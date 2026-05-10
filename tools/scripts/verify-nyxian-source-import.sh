#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

required_paths=(
  "ThirdParty/Nyxian/Nyxian.xcodeproj/project.pbxproj"
  "ThirdParty/Nyxian/MobileDevelopmentKit/Tools/Compiler/MDKSwiftCompiler.m"
  "ThirdParty/Nyxian/Nyxian/LindChain/Core/Builder.swift"
  "ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/LCUtils.m"
  "ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/LCMachOUtils.m"
  "ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/LCBootstrap.m"
  "ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/ZSign/zsigner.m"
  "ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/ZSign/openssl.cpp"
  "ThirdParty/Nyxian/Nyxian/LindChain/OpenSSL.xcframework/Info.plist"
  "ThirdParty/Nyxian/Nyxian/LindChain/OpenSSL.xcframework/ios-arm64/OpenSSL.framework/OpenSSL"
  "ThirdParty/LLVM-On-iOS/Scripts/build-swift-toolchain.sh"
  "ThirdParty/Nyxian/VENDOR_LOCK.json"
  "apps/ios/Sources/Litter/Resources/BuildKit/nyxian-import-manifest.json"
)

missing=0
for rel in "${required_paths[@]}"; do
  if [[ -e "$ROOT_DIR/$rel" ]]; then
    echo "ok  $rel"
  else
    echo "bad $rel" >&2
    missing=1
  fi
done

python3 - "$ROOT_DIR" <<'PYVERIFY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
lock = json.loads((root / "ThirdParty/Nyxian/VENDOR_LOCK.json").read_text())
manifest = json.loads((root / "apps/ios/Sources/Litter/Resources/BuildKit/nyxian-import-manifest.json").read_text())
if "Nyxian/LindChain/OpenSSL.xcframework" in lock.get("excludedHeavyOrIrrelevantPaths", []):
    raise SystemExit("bad VENDOR_LOCK excludes OpenSSL.xcframework")
for rel in lock.get("requiredBuildKitPaths", []):
    if not (root / rel).exists():
        raise SystemExit(f"bad VENDOR_LOCK required path missing: {rel}")
live = manifest.get("liveContainer") or {}
if not live.get("sourceIncluded") or not live.get("zsignIncluded") or not live.get("openSSLFrameworkIncluded"):
    raise SystemExit("bad nyxian-import-manifest LiveContainer/OpenSSL flags")
print("ok  source import JSON manifests")
PYVERIFY

if [[ "$missing" != "0" ]]; then
  exit 1
fi
