#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYXIAN_REPO="${NYXIAN_REPO:-https://github.com/ProjectNyxian/Nyxian.git}"
LLVM_REPO="${LLVM_ON_IOS_REPO:-https://github.com/ProjectNyxian/LLVM-On-iOS.git}"
NYXIAN_REF="${NYXIAN_REF:-main}"
LLVM_REF="${LLVM_ON_IOS_REF:-main}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

copy_tree() {
  local src="$1"
  local dst="$2"
  rm -rf "$dst"
  mkdir -p "$dst"
  (
    cd "$src"
    tar \
      --exclude .git \
      --exclude build \
      --exclude Payload \
      --exclude .package \
      --exclude '*.ipa' \
      --exclude '*.tipa' \
      --exclude '*.deb' \
      -cf - .
  ) | (cd "$dst" && tar -xf -)
}

echo "==> Cloning Nyxian source: $NYXIAN_REPO@$NYXIAN_REF"
git clone --depth 1 --branch "$NYXIAN_REF" --recurse-submodules "$NYXIAN_REPO" "$TMP_DIR/Nyxian"
NYXIAN_COMMIT="$(git -C "$TMP_DIR/Nyxian" rev-parse HEAD)"

LITTER_NATIVE_BACKUP="$TMP_DIR/LitterBuildKitNative"
if [[ -d "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative" ]]; then
  cp -R "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative" "$LITTER_NATIVE_BACKUP"
fi

mkdir -p "$ROOT_DIR/ThirdParty"
copy_tree "$TMP_DIR/Nyxian" "$ROOT_DIR/ThirdParty/Nyxian"
if [[ -d "$LITTER_NATIVE_BACKUP" ]]; then
  rm -rf "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative"
  cp -R "$LITTER_NATIVE_BACKUP" "$ROOT_DIR/ThirdParty/Nyxian/LitterBuildKitNative"
fi

LLVM_COMMIT=""
if git ls-remote --exit-code "$LLVM_REPO" "$LLVM_REF" >/dev/null 2>&1; then
  echo "==> Cloning LLVM-On-iOS source: $LLVM_REPO@$LLVM_REF"
  git clone --depth 1 --branch "$LLVM_REF" "$LLVM_REPO" "$TMP_DIR/LLVM-On-iOS"
  LLVM_COMMIT="$(git -C "$TMP_DIR/LLVM-On-iOS" rev-parse HEAD)"
  copy_tree "$TMP_DIR/LLVM-On-iOS" "$ROOT_DIR/ThirdParty/LLVM-On-iOS"
elif [[ -d "$ROOT_DIR/ThirdParty/Nyxian/LLVM-On-iOS" ]]; then
  echo "==> Using Nyxian submodule copy for ThirdParty/LLVM-On-iOS"
  copy_tree "$ROOT_DIR/ThirdParty/Nyxian/LLVM-On-iOS" "$ROOT_DIR/ThirdParty/LLVM-On-iOS"
else
  echo "warning: could not clone LLVM-On-iOS and Nyxian submodule copy was missing" >&2
fi

python3 - "$ROOT_DIR/ThirdParty/Nyxian/VENDOR_LOCK.json" "$NYXIAN_REPO" "$NYXIAN_REF" "$NYXIAN_COMMIT" "$LLVM_REPO" "$LLVM_REF" "$LLVM_COMMIT" <<'PYVENDOR'
import datetime, json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = {
    "schemaVersion": 1,
    "updatedAt": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
    "nyxian": {"repo": sys.argv[2], "ref": sys.argv[3], "commit": sys.argv[4]},
    "llvmOnIOS": {"repo": sys.argv[5], "ref": sys.argv[6], "commit": sys.argv[7]},
    "litterPreservedPaths": ["ThirdParty/Nyxian/LitterBuildKitNative"],
}
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PYVENDOR

echo "==> Vendored Nyxian at $NYXIAN_COMMIT"
if [[ -n "$LLVM_COMMIT" ]]; then echo "==> Vendored LLVM-On-iOS at $LLVM_COMMIT"; fi
