#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYXIAN_REPO="${NYXIAN_REPO:-https://github.com/ProjectNyxian/Nyxian.git}"
LLVM_REPO="${LLVM_ON_IOS_REPO:-https://github.com/ProjectNyxian/LLVM-On-iOS.git}"
NYXIAN_REF="${NYXIAN_REF:-main}"
LLVM_REF="${LLVM_ON_IOS_REF:-master}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ "$(uname -s)" != "Darwin" && "${NYXIAN_VENDOR_ALLOW_NON_DARWIN:-0}" != "1" ]]; then
  cat >&2 <<'EOF'
Refusing to refresh Nyxian from this non-macOS shell by default.
The iSH Alpine fakefs network path is too slow/unreliable for the full upstream tree.
Run `make nyxian-vendor` on macOS or set NYXIAN_VENDOR_ALLOW_NON_DARWIN=1 if you accept a slow best-effort refresh.
EOF
  exit 64
fi

EXCLUDES=(
  --exclude .git
  --exclude .gitmodules
  --exclude .github
  --exclude build
  --exclude DerivedData
  --exclude Payload
  --exclude .package
  --exclude tmp
  --exclude .DS_Store
  --exclude '*.ipa'
  --exclude '*.tipa'
  --exclude '*.deb'
  --exclude '*.xcuserstate'
  --exclude '*/xcuserdata/*'
  --exclude 'Nyxian/Assets.xcassets'
  --exclude TrollStore
  --exclude libroot
)

copy_tree() {
  local src="$1"
  local dst="$2"
  local stage="$TMP_DIR/stage-$(basename "$dst")"
  rm -rf "$stage"
  mkdir -p "$stage"
  (
    cd "$src"
    tar "${EXCLUDES[@]}" -cf - .
  ) | (cd "$stage" && tar -xf -)
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  mv "$stage" "$dst"
}

trim_openssl_ios_slice() {
  local framework_root="$ROOT_DIR/ThirdParty/Nyxian/Nyxian/LindChain/OpenSSL.xcframework"
  [[ -d "$framework_root" ]] || return 0
  find "$framework_root" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'ios-arm64' \
    ! -name '_CodeSignature' \
    -exec rm -rf {} +
  python3 - "$framework_root/Info.plist" <<'PYPLIST'
import plistlib
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = plistlib.loads(path.read_bytes())
data["AvailableLibraries"] = [
    lib for lib in data.get("AvailableLibraries", [])
    if lib.get("LibraryIdentifier") == "ios-arm64"
]
path.write_bytes(plistlib.dumps(data, sort_keys=False))
PYPLIST
}

clone_repo() {
  local repo="$1"
  local ref="$2"
  local dst="$3"
  git -c http.version=HTTP/1.1 clone --depth 1 --branch "$ref" "$repo" "$dst"
}

LITTER_NATIVE_BACKUP="$TMP_DIR/LitterBuildKitNative"
if [[ -d "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative" ]]; then
  cp -R "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative" "$LITTER_NATIVE_BACKUP"
fi

clone_repo "$NYXIAN_REPO" "$NYXIAN_REF" "$TMP_DIR/Nyxian"
NYXIAN_COMMIT="$(git -C "$TMP_DIR/Nyxian" rev-parse HEAD)"
copy_tree "$TMP_DIR/Nyxian" "$ROOT_DIR/ThirdParty/Nyxian"
trim_openssl_ios_slice

if [[ -d "$LITTER_NATIVE_BACKUP" ]]; then
  rm -rf "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative"
  cp -R "$LITTER_NATIVE_BACKUP" "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative"
fi

clone_repo "$LLVM_REPO" "$LLVM_REF" "$TMP_DIR/LLVM-On-iOS"
LLVM_COMMIT="$(git -C "$TMP_DIR/LLVM-On-iOS" rev-parse HEAD)"
copy_tree "$TMP_DIR/LLVM-On-iOS" "$ROOT_DIR/ThirdParty/LLVM-On-iOS"
copy_tree "$TMP_DIR/LLVM-On-iOS" "$ROOT_DIR/ThirdParty/Nyxian/LLVM-On-iOS"

required_paths=(
  "$ROOT_DIR/ThirdParty/Nyxian/Nyxian.xcodeproj/project.pbxproj"
  "$ROOT_DIR/ThirdParty/Nyxian/MobileDevelopmentKit/Tools/Compiler/MDKSwiftCompiler.m"
  "$ROOT_DIR/ThirdParty/Nyxian/Nyxian/LindChain/Core/Builder.swift"
  "$ROOT_DIR/ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/LCUtils.m"
  "$ROOT_DIR/ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/ZSign/zsigner.m"
  "$ROOT_DIR/ThirdParty/Nyxian/Nyxian/LindChain/OpenSSL.xcframework/Info.plist"
  "$ROOT_DIR/ThirdParty/Nyxian/Nyxian/LindChain/OpenSSL.xcframework/ios-arm64/OpenSSL.framework/OpenSSL"
  "$ROOT_DIR/ThirdParty/LLVM-On-iOS/Scripts/build-swift-toolchain.sh"
)
for required_path in "${required_paths[@]}"; do
  if [[ ! -f "$required_path" ]]; then
    echo "error: vendored tree is missing $required_path" >&2
    exit 1
  fi
done

NYXIAN_FILE_COUNT="$(find "$ROOT_DIR/ThirdParty/Nyxian" -type f | wc -l | tr -d ' ')"
LLVM_FILE_COUNT="$(find "$ROOT_DIR/ThirdParty/LLVM-On-iOS" -type f | wc -l | tr -d ' ')"

python3 - "$ROOT_DIR/ThirdParty/Nyxian/VENDOR_LOCK.json" \
  "$NYXIAN_REPO" "$NYXIAN_REF" "$NYXIAN_COMMIT" "$NYXIAN_FILE_COUNT" \
  "$LLVM_REPO" "$LLVM_REF" "$LLVM_COMMIT" "$LLVM_FILE_COUNT" <<'PYVENDOR'
import datetime
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = {
    "schemaVersion": 3,
    "updatedAt": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
    "vendoringMode": "focused-buildkit-source-import",
    "nyxian": {"repo": sys.argv[2], "ref": sys.argv[3], "commit": sys.argv[4], "vendoredFileCount": int(sys.argv[5])},
    "llvmOnIOS": {"repo": sys.argv[6], "ref": sys.argv[7], "commit": sys.argv[8], "vendoredFileCount": int(sys.argv[9])},
    "litterPreservedPaths": ["ThirdParty/Nyxian/LitterBuildKitNative"],
    "excludedHeavyOrIrrelevantPaths": ["Nyxian/Assets.xcassets", "TrollStore", "libroot", ".github", ".gitignore", ".gitattributes"],
    "requiredBuildKitPaths": [
        "ThirdParty/Nyxian/Nyxian.xcodeproj/project.pbxproj",
        "ThirdParty/Nyxian/MobileDevelopmentKit/Tools/Compiler/MDKSwiftCompiler.m",
        "ThirdParty/Nyxian/Nyxian/LindChain/Core/Builder.swift",
        "ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/LCUtils.m",
        "ThirdParty/Nyxian/Nyxian/LindChain/LiveContainer/ZSign/zsigner.m",
        "ThirdParty/Nyxian/Nyxian/LindChain/OpenSSL.xcframework/Info.plist",
        "ThirdParty/Nyxian/Nyxian/LindChain/OpenSSL.xcframework/ios-arm64/OpenSSL.framework/OpenSSL",
        "ThirdParty/LLVM-On-iOS/Scripts/build-swift-toolchain.sh",
    ],
}
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PYVENDOR

echo "==> Vendored focused Nyxian BuildKit source at $NYXIAN_COMMIT ($NYXIAN_FILE_COUNT files)"
echo "==> Vendored LLVM-On-iOS at $LLVM_COMMIT ($LLVM_FILE_COUNT files)"
