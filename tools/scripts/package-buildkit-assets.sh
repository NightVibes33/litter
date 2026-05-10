#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${LITTER_BUILDKIT_OUT_DIR:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets}"
ZIP_PATH="${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}"
CORECOMPILER_FRAMEWORK="${CORECOMPILER_FRAMEWORK:-}"
NATIVE_DRIVER_FRAMEWORK="${LITTER_BUILDKIT_NATIVE_FRAMEWORK:-}"
SUPPORT_LIBS="${CORECOMPILER_SUPPORT_LIBS:-}"
IPHONEOS_SDK_PATH="${IPHONEOS_SDK_PATH:-}"
SDK_VERSION="${LITTER_BUILDKIT_SDK_VERSION:-26.4}"
SWIFT_VERSION="${LITTER_BUILDKIT_SWIFT_VERSION:-6.x}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: package-buildkit-assets.sh must run on macOS with Xcode available" >&2
  exit 1
fi

if [[ -z "${IPHONEOS_SDK_PATH}" ]]; then
  IPHONEOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
fi

require_path() {
  local label="$1"
  local path="$2"
  if [[ -z "$path" || ! -e "$path" ]]; then
    echo "error: missing $label: $path" >&2
    exit 1
  fi
}

require_path "CoreCompiler.framework" "$CORECOMPILER_FRAMEWORK"
require_path "LitterBuildKitNative.framework" "$NATIVE_DRIVER_FRAMEWORK"
require_path "CoreCompilerSupportLibs" "$SUPPORT_LIBS"
require_path "iPhoneOS SDK" "$IPHONEOS_SDK_PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Toolchains/Nyxian" "$OUT_DIR/SDK" "$(dirname "$ZIP_PATH")"
cp -R "$CORECOMPILER_FRAMEWORK" "$OUT_DIR/Toolchains/Nyxian/CoreCompiler.framework"
cp -R "$NATIVE_DRIVER_FRAMEWORK" "$OUT_DIR/Toolchains/Nyxian/LitterBuildKitNative.framework"
cp -R "$SUPPORT_LIBS" "$OUT_DIR/Toolchains/Nyxian/CoreCompilerSupportLibs"
cp -R "$IPHONEOS_SDK_PATH" "$OUT_DIR/SDK/iPhoneOS${SDK_VERSION}.sdk"

python3 - "$OUT_DIR" "$SDK_VERSION" "$SWIFT_VERSION" <<'PY'
import datetime, hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sdk_version = sys.argv[2]
swift_version = sys.argv[3]
required = [
    "Toolchains/Nyxian/CoreCompiler.framework",
    "Toolchains/Nyxian/LitterBuildKitNative.framework",
    "Toolchains/Nyxian/CoreCompilerSupportLibs",
    f"SDK/iPhoneOS{sdk_version}.sdk/SDKSettings.plist",
]
hashes = {}
for path in sorted(root.rglob("*")):
    if path.is_file() and path.stat().st_size <= 64 * 1024 * 1024:
        rel = path.relative_to(root).as_posix()
        h = hashlib.sha256()
        with path.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                h.update(chunk)
        hashes[rel] = h.hexdigest()
manifest = {
    "schemaVersion": 1,
    "bundleIdentifier": "com.sigkitten.litter.buildkit.private",
    "createdAt": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
    "sdkVersion": sdk_version,
    "swiftVersion": swift_version,
    "minimumIOS": "18.0",
    "toolchain": {
        "name": "Nyxian/CoreCompiler",
        "coreCompilerFramework": "Toolchains/Nyxian/CoreCompiler.framework",
        "nativeDriverFramework": "Toolchains/Nyxian/LitterBuildKitNative.framework",
        "supportLibraries": "Toolchains/Nyxian/CoreCompilerSupportLibs",
        "sdkPath": f"SDK/iPhoneOS{sdk_version}.sdk",
    },
    "capabilities": ["swift-check", "swift-build", "swift-test", "unsigned-ipa-build", "unsigned-ipa-package"],
    "requiredPaths": required,
    "sha256": hashes,
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY

rm -f "$ZIP_PATH"
(
  cd "$(dirname "$OUT_DIR")"
  /usr/bin/zip -qry "$ZIP_PATH" "$(basename "$OUT_DIR")"
)

echo "BuildKit assets staged at $OUT_DIR"
echo "BuildKit assets zipped at  $ZIP_PATH"
