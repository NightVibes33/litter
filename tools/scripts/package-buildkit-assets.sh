#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${LITTER_BUILDKIT_OUT_DIR:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets}"
ZIP_PATH="${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}"
CORECOMPILER_FRAMEWORK="${CORECOMPILER_FRAMEWORK:-}"
NATIVE_DRIVER_FRAMEWORK="${LITTER_BUILDKIT_NATIVE_FRAMEWORK:-}"
NYXIAN_RUNNER="${NYXIAN_BUILDKIT_RUNNER:-}"
NATIVE_MODE="${LITTER_BUILDKIT_NATIVE_MODE:-inprocess}"
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
if [[ -z "$NATIVE_DRIVER_FRAMEWORK" ]]; then
  echo "==> LITTER_BUILDKIT_NATIVE_FRAMEWORK not set; building the default native wrapper"
  LITTER_BUILDKIT_NATIVE_MODE="$NATIVE_MODE" CORECOMPILER_FRAMEWORK="$CORECOMPILER_FRAMEWORK" "$ROOT_DIR/tools/scripts/build-litter-buildkit-native.sh"
  NATIVE_DRIVER_FRAMEWORK="$ROOT_DIR/artifacts/buildkit/LitterBuildKitNative.framework"
fi
require_path "LitterBuildKitNative.framework" "$NATIVE_DRIVER_FRAMEWORK"
require_path "CoreCompilerSupportLibs" "$SUPPORT_LIBS"
if [[ "$NATIVE_MODE" = "runner" && -z "$NYXIAN_RUNNER" ]]; then
  echo "error: LITTER_BUILDKIT_NATIVE_MODE=runner requires NYXIAN_BUILDKIT_RUNNER=/path/to/runner" >&2
  echo "       Use LITTER_BUILDKIT_NATIVE_MODE=inprocess for the embedded CoreCompiler bridge." >&2
  exit 1
fi
if [[ -n "$NYXIAN_RUNNER" ]]; then
  require_path "Nyxian BuildKit runner" "$NYXIAN_RUNNER"
fi
require_path "iPhoneOS SDK" "$IPHONEOS_SDK_PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Toolchains/Nyxian" "$OUT_DIR/SDK" "$(dirname "$ZIP_PATH")"
cp -R "$CORECOMPILER_FRAMEWORK" "$OUT_DIR/Toolchains/Nyxian/CoreCompiler.framework"
cp -R "$NATIVE_DRIVER_FRAMEWORK" "$OUT_DIR/Toolchains/Nyxian/LitterBuildKitNative.framework"
cp -R "$SUPPORT_LIBS" "$OUT_DIR/Toolchains/Nyxian/CoreCompilerSupportLibs"
cp -R "$IPHONEOS_SDK_PATH" "$OUT_DIR/SDK/iPhoneOS${SDK_VERSION}.sdk"
RUNNER_REL=""
if [[ -n "$NYXIAN_RUNNER" ]]; then
  mkdir -p "$OUT_DIR/Toolchains/Nyxian/bin"
  cp "$NYXIAN_RUNNER" "$OUT_DIR/Toolchains/Nyxian/bin/litter-buildkit-runner"
  chmod +x "$OUT_DIR/Toolchains/Nyxian/bin/litter-buildkit-runner"
  RUNNER_REL="Toolchains/Nyxian/bin/litter-buildkit-runner"
fi

python3 - "$OUT_DIR" "$SDK_VERSION" "$SWIFT_VERSION" "$RUNNER_REL" "$NATIVE_MODE" <<'PY'
import datetime, hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sdk_version = sys.argv[2]
swift_version = sys.argv[3]
runner_rel = sys.argv[4]
native_mode = sys.argv[5]
required = [
    "Toolchains/Nyxian/CoreCompiler.framework",
    "Toolchains/Nyxian/LitterBuildKitNative.framework",
    "Toolchains/Nyxian/CoreCompilerSupportLibs",
    f"SDK/iPhoneOS{sdk_version}.sdk/SDKSettings.plist",
]
if runner_rel:
    required.append(runner_rel)
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
        "nativeRunner": runner_rel or None,
        "nativeDriverMode": native_mode,
        "supportLibraries": "Toolchains/Nyxian/CoreCompilerSupportLibs",
        "sdkPath": f"SDK/iPhoneOS{sdk_version}.sdk",
    },
    "capabilities": ["swift-check", "swift-build", "swift-test", "unsigned-ipa-build", "unsigned-ipa-package"] + (["nyxian-runner"] if runner_rel else []) + (["in-process-native-driver", "in-process-ipa-packager"] if native_mode == "inprocess" else ["runner-native-driver"]),
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
