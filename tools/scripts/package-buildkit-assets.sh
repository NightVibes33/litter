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
CLANG_RESOURCE_DIR="${LITTER_BUILDKIT_CLANG_RESOURCE_DIR:-${CLANG_RESOURCE_DIR:-}}"
CXX_STANDARD_LIBRARY_INCLUDE_DIR="${LITTER_BUILDKIT_CXX_STANDARD_LIBRARY_INCLUDE_DIR:-${CXX_STANDARD_LIBRARY_INCLUDE_DIR:-}}"
SDK_VERSION="${LITTER_BUILDKIT_SDK_VERSION:-}"
SWIFT_VERSION="${LITTER_BUILDKIT_SWIFT_VERSION:-6.x}"
SWIFT_COMPATIBILITY_VERSION="${LITTER_BUILDKIT_SWIFT_COMPATIBILITY_VERSION:-$SWIFT_VERSION}"
SDK_SWIFT_VERSION="${LITTER_BUILDKIT_SDK_SWIFT_VERSION:-}"
SOURCE_COMMIT="${LITTER_BUILDKIT_SOURCE_COMMIT:-}"
NATIVE_SOURCE_FINGERPRINT="${LITTER_BUILDKIT_NATIVE_SOURCE_FINGERPRINT:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: package-buildkit-assets.sh must run on macOS with Xcode available" >&2
  exit 1
fi

if [[ -z "${IPHONEOS_SDK_PATH}" ]]; then
  IPHONEOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
fi
if [[ -z "$SDK_VERSION" ]]; then
  SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
fi
CLANG_BIN="$(xcrun --sdk iphoneos --find clang)"
if [[ -z "$CLANG_RESOURCE_DIR" ]]; then
  CLANG_RESOURCE_DIR="$("$CLANG_BIN" -print-resource-dir)"
fi
find_cxx_standard_library_include_dir() {
  local toolchain_usr_dir
  toolchain_usr_dir="$(cd "$(dirname "$CLANG_BIN")/.." && pwd -P)"
  local developer_dir
  developer_dir="$(xcode-select -p)"
  local candidate
  for candidate in \
    "$toolchain_usr_dir/include/c++/v1" \
    "$toolchain_usr_dir/lib/c++/v1" \
    "$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/include/c++/v1" \
    "$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/lib/c++/v1" \
    "$IPHONEOS_SDK_PATH/usr/include/c++/v1"; do
    if [[ -f "$candidate/vector" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  # Xcode occasionally moves libc++ headers. Ask clang for the active C++
  # search paths and choose the first directory containing the vector header.
  local search_log
  search_log="$(mktemp)"
  printf '#include <vector>\n' | "$CLANG_BIN" \
    -target "arm64-apple-ios${IOS_DEPLOYMENT_TARGET:-18.0}" \
    -isysroot "$IPHONEOS_SDK_PATH" \
    -x c++ \
    -std=c++17 \
    -E \
    -v \
    - >/dev/null 2>"$search_log" || true
  while IFS= read -r candidate; do
    candidate="${candidate#"${candidate%%[![:space:]]*}"}"
    candidate="${candidate% (framework directory)}"
    if [[ -f "$candidate/vector" ]]; then
      rm -f "$search_log"
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(awk '/#include <...> search starts here:/{capture=1; next} /End of search list./{capture=0} capture {print}' "$search_log")
  echo "warning: unable to locate libc++ headers from clang search paths:" >&2
  sed 's/^/  /' "$search_log" >&2
  rm -f "$search_log"
  return 1
}
if [[ -z "$CXX_STANDARD_LIBRARY_INCLUDE_DIR" ]]; then
  CXX_STANDARD_LIBRARY_INCLUDE_DIR="$(find_cxx_standard_library_include_dir || true)"
fi
if [[ -z "$SDK_SWIFT_VERSION" ]]; then
  SDK_SWIFT_VERSION="$(xcrun --find swift >/dev/null 2>&1 && swift --version | head -n 1 || true)"
fi

if [[ -z "$SOURCE_COMMIT" ]]; then
  SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
fi
if [[ -z "$NATIVE_SOURCE_FINGERPRINT" ]]; then
  NATIVE_SOURCE_FINGERPRINT="$("$ROOT_DIR/tools/scripts/buildkit-native-source-fingerprint.sh")"
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
if [[ -f "$CORECOMPILER_FRAMEWORK/CoreCompiler.tbd" && ! -f "$CORECOMPILER_FRAMEWORK/CoreCompiler" ]]; then
  echo "error: CoreCompiler.framework only contains CoreCompiler.tbd; rebuild assets with the real framework product" >&2
  exit 1
fi
require_path "CoreCompiler.framework executable" "$CORECOMPILER_FRAMEWORK/CoreCompiler"
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
if [[ -d "$IPHONEOS_SDK_PATH" ]]; then
  IPHONEOS_SDK_PATH="$(cd "$IPHONEOS_SDK_PATH" && pwd -P)"
fi
require_path "iPhoneOS SDK" "$IPHONEOS_SDK_PATH"
if [[ -d "$CLANG_RESOURCE_DIR" ]]; then
  CLANG_RESOURCE_DIR="$(cd "$CLANG_RESOURCE_DIR" && pwd -P)"
fi
require_path "Clang resource directory" "$CLANG_RESOURCE_DIR"
require_path "Clang builtin header stdarg.h" "$CLANG_RESOURCE_DIR/include/stdarg.h"
require_path "Clang builtin header stdbool.h" "$CLANG_RESOURCE_DIR/include/stdbool.h"
require_path "Clang builtin header stddef.h" "$CLANG_RESOURCE_DIR/include/stddef.h"
if [[ -d "$CXX_STANDARD_LIBRARY_INCLUDE_DIR" ]]; then
  CXX_STANDARD_LIBRARY_INCLUDE_DIR="$(cd "$CXX_STANDARD_LIBRARY_INCLUDE_DIR" && pwd -P)"
fi
require_path "libc++ standard library headers" "$CXX_STANDARD_LIBRARY_INCLUDE_DIR"
require_path "libc++ vector header" "$CXX_STANDARD_LIBRARY_INCLUDE_DIR/vector"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Toolchains/Nyxian" "$OUT_DIR/SDK" "$(dirname "$ZIP_PATH")"
cp -R "$CORECOMPILER_FRAMEWORK" "$OUT_DIR/Toolchains/Nyxian/CoreCompiler.framework"
cp -R "$NATIVE_DRIVER_FRAMEWORK" "$OUT_DIR/Toolchains/Nyxian/LitterBuildKitNative.framework"
cp -R "$SUPPORT_LIBS" "$OUT_DIR/Toolchains/Nyxian/CoreCompilerSupportLibs"
CLANG_RESOURCE_REL="Toolchains/Nyxian/ClangResourceDir"
CLANG_RESOURCE_DEST="$OUT_DIR/$CLANG_RESOURCE_REL"
rm -rf "$CLANG_RESOURCE_DEST"
/usr/bin/ditto "$CLANG_RESOURCE_DIR" "$CLANG_RESOURCE_DEST"
CXX_INCLUDE_REL="Toolchains/Nyxian/CxxStandardLibrary/include/c++/v1"
CXX_INCLUDE_DEST="$OUT_DIR/$CXX_INCLUDE_REL"
rm -rf "$OUT_DIR/Toolchains/Nyxian/CxxStandardLibrary"
mkdir -p "$(dirname "$CXX_INCLUDE_DEST")"
/usr/bin/ditto "$CXX_STANDARD_LIBRARY_INCLUDE_DIR" "$CXX_INCLUDE_DEST"
SDK_DEST="$OUT_DIR/SDK/iPhoneOS${SDK_VERSION}.sdk"
rm -rf "$SDK_DEST"
/usr/bin/ditto "$IPHONEOS_SDK_PATH" "$SDK_DEST"
RUNNER_REL=""
if [[ -n "$NYXIAN_RUNNER" ]]; then
  mkdir -p "$OUT_DIR/Toolchains/Nyxian/bin"
  cp "$NYXIAN_RUNNER" "$OUT_DIR/Toolchains/Nyxian/bin/litter-buildkit-runner"
  chmod +x "$OUT_DIR/Toolchains/Nyxian/bin/litter-buildkit-runner"
  RUNNER_REL="Toolchains/Nyxian/bin/litter-buildkit-runner"
fi

normalize_buildkit_payload_symlinks() {
  echo "==> Normalizing BuildKit asset symlinks"
  local normalized_dir
  normalized_dir="$(mktemp -d)"
  cp -R -L "$OUT_DIR" "$normalized_dir/$(basename "$OUT_DIR")"
  if find "$normalized_dir/$(basename "$OUT_DIR")" -type l -print -quit | grep -q .; then
    echo "error: normalized BuildKit asset output still contains symlinks" >&2
    find "$normalized_dir/$(basename "$OUT_DIR")" -type l -print | sed -n '1,200p' >&2
    rm -rf "$normalized_dir"
    exit 1
  fi
  rm -rf "$OUT_DIR"
  mv "$normalized_dir/$(basename "$OUT_DIR")" "$OUT_DIR"
  rm -rf "$normalized_dir"
}

prune_sdk_compiler_dylibs() {
  echo "==> Pruning SDK compiler dylibs from BuildKit assets"
  find "$OUT_DIR/SDK" -type f \( \
    -name 'lib_Compiler*.dylib' -o \
    -name 'libLLVM*.dylib' -o \
    -name 'libllvm*.dylib' \
  \) -print | sort -u | while IFS= read -r library; do
    echo "removed: ${library#$OUT_DIR/}"
    rm -f "$library"
  done
}

is_macho_binary() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  /usr/bin/file "$path" 2>/dev/null | /usr/bin/grep -Eiq 'Mach-O'
}

sign_macho_binary() {
  local path="$1"
  is_macho_binary "$path" || return 0
  chmod u+w "$path" 2>/dev/null || true
  /usr/bin/codesign --force --sign - --timestamp=none "$path"
  local signature_info
  signature_info="$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1)" || {
    echo "error: failed to sign BuildKit Mach-O payload: $path" >&2
    printf '%s\n' "$signature_info" >&2
    exit 1
  }
  if ! printf '%s\n' "$signature_info" | /usr/bin/grep -Eq 'CDHash=|CodeDirectory'; then
    echo "error: BuildKit Mach-O payload is missing a code directory/CDHash after signing: $path" >&2
    printf '%s\n' "$signature_info" >&2
    exit 1
  fi
  echo "signed: ${path#$OUT_DIR/}"
}

sign_buildkit_payload() {
  echo "==> Ad-hoc signing BuildKit Mach-O payloads"
  find "$OUT_DIR/Toolchains/Nyxian" -type f \( \
    -name 'CoreCompiler' -o \
    -name 'LitterBuildKitNative' -o \
    -name 'litter-buildkit-runner' -o \
    -name 'lib_Compiler*.dylib' -o \
    -name 'libLLVM*.dylib' -o \
    -name 'libllvm*.dylib' \
  \) -print | sort -u | while IFS= read -r binary; do
    sign_macho_binary "$binary"
  done
  find "$OUT_DIR/SDK" -type f -name '*.dylib' -print | sort -u | while IFS= read -r binary; do
    sign_macho_binary "$binary"
  done
}

normalize_buildkit_payload_symlinks
prune_sdk_compiler_dylibs
sign_buildkit_payload

python3 - "$OUT_DIR" "$SDK_VERSION" "$SWIFT_VERSION" "$SWIFT_COMPATIBILITY_VERSION" "$SDK_SWIFT_VERSION" "$RUNNER_REL" "$NATIVE_MODE" "$SOURCE_COMMIT" "$NATIVE_SOURCE_FINGERPRINT" "$CLANG_RESOURCE_REL" "$CXX_INCLUDE_REL" <<'PY'
import datetime, hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sdk_version = sys.argv[2]
swift_version = sys.argv[3]
swift_compatibility_version = sys.argv[4]
sdk_swift_version = sys.argv[5]
runner_rel = sys.argv[6]
native_mode = sys.argv[7]
source_commit = sys.argv[8]
native_source_fingerprint = sys.argv[9]
clang_resource_rel = sys.argv[10]
cxx_include_rel = sys.argv[11]
required = [
    "Toolchains/Nyxian/CoreCompiler.framework",
    "Toolchains/Nyxian/CoreCompiler.framework/CoreCompiler",
    "Toolchains/Nyxian/LitterBuildKitNative.framework",
    "Toolchains/Nyxian/LitterBuildKitNative.framework/LitterBuildKitNative",
    "Toolchains/Nyxian/CoreCompilerSupportLibs",
    clang_resource_rel,
    f"{clang_resource_rel}/include/stdarg.h",
    f"{clang_resource_rel}/include/stdbool.h",
    f"{clang_resource_rel}/include/stddef.h",
    cxx_include_rel,
    f"{cxx_include_rel}/vector",
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
    "swiftCompatibilityVersion": swift_compatibility_version,
    "sdkSwiftVersion": sdk_swift_version or None,
    "sourceCommit": source_commit or None,
    "nativeDriverSourceFingerprint": native_source_fingerprint,
    "source": {
        "repositoryCommit": source_commit or None,
        "nativeDriverSourceFingerprint": native_source_fingerprint,
    },
    "minimumIOS": "18.0",
    "toolchain": {
        "name": "Nyxian/CoreCompiler",
        "coreCompilerFramework": "Toolchains/Nyxian/CoreCompiler.framework",
        "nativeDriverFramework": "Toolchains/Nyxian/LitterBuildKitNative.framework",
        "nativeRunner": runner_rel or None,
        "nativeDriverMode": native_mode,
        "supportLibraries": "Toolchains/Nyxian/CoreCompilerSupportLibs",
        "sdkPath": f"SDK/iPhoneOS{sdk_version}.sdk",
        "clangResourceDir": clang_resource_rel,
        "cxxStandardLibraryIncludeDir": cxx_include_rel,
    },
    "capabilities": ["swift-check", "swift-build", "swift-test", "unsigned-ipa-build", "unsigned-ipa-package", "clang-ios-build", "objc-ios-build", "cxx-ios-build", "objcxx-ios-build", "ld-ios-link", "xcrun-compat", "plutil-compat", "clang-resource-dir", "cxx-stdlib-headers", "ui-framework-imports"] + (["nyxian-runner"] if runner_rel else []) + (["in-process-native-driver", "in-process-ipa-packager"] if native_mode == "inprocess" else ["runner-native-driver"]),
    "requiredPaths": required,
    "sha256": hashes,
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY

rm -f "$ZIP_PATH"
(
  if find "$OUT_DIR" -type l -print -quit | grep -q .; then
    echo "error: BuildKit asset output still contains symlinks" >&2
    find "$OUT_DIR" -type l -print | sed -n '1,200p' >&2
    exit 1
  fi
  cd "$(dirname "$OUT_DIR")"
  /usr/bin/zip -qry "$ZIP_PATH" "$(basename "$OUT_DIR")"
)

echo "BuildKit assets staged at $OUT_DIR"
echo "BuildKit assets zipped at  $ZIP_PATH"
