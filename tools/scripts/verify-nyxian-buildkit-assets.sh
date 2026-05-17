#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT="${1:-${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -z "${LITTER_BUILDKIT_EXPECT_NATIVE_SOURCE_FINGERPRINT:-}" && -x "$ROOT_DIR/tools/scripts/buildkit-native-source-fingerprint.sh" ]]; then
  export LITTER_BUILDKIT_EXPECT_NATIVE_SOURCE_FINGERPRINT="$("$ROOT_DIR/tools/scripts/buildkit-native-source-fingerprint.sh" 2>/dev/null || true)"
fi

if [[ ! -e "$INPUT" ]]; then
  echo "error: BuildKit asset input does not exist: $INPUT" >&2
  exit 1
fi

if [[ -d "$INPUT" ]]; then
  ASSET_ROOT="$INPUT"
else
  python3 - "$INPUT" <<'PYZIP'
import pathlib, stat, sys, zipfile
zip_path = pathlib.Path(sys.argv[1])
bad = []
with zipfile.ZipFile(zip_path) as archive:
    for info in archive.infolist():
        mode = (info.external_attr >> 16) & 0o170000
        if mode == stat.S_IFLNK:
            bad.append(info.filename)
if bad:
    print("error: BuildKit asset ZIP contains symlinks that iOS ZIPFoundation refuses to extract:")
    for name in bad[:200]:
        print(f"- {name}")
    raise SystemExit(1)
PYZIP
  unzip -q "$INPUT" -d "$TMP_DIR/unzipped"
  MANIFEST="$(find "$TMP_DIR/unzipped" -maxdepth 3 -name manifest.json -print | head -n 1)"
  if [[ -z "$MANIFEST" ]]; then
    echo "error: asset ZIP did not contain manifest.json" >&2
    exit 1
  fi
  ASSET_ROOT="$(dirname "$MANIFEST")"
fi

if find "$ASSET_ROOT" -type l -print -quit | grep -q .; then
  echo "error: BuildKit asset directory contains symlinks that iOS ZIPFoundation refuses to extract:" >&2
  find "$ASSET_ROOT" -type l -print | sed -n '1,200p' >&2
  exit 1
fi

python3 - "$ASSET_ROOT" <<'PYVERIFY'
import hashlib, json, os, pathlib, sys
root = pathlib.Path(sys.argv[1])
manifest_path = root / "manifest.json"
manifest = json.loads(manifest_path.read_text())
toolchain = manifest.get("toolchain", {})
required = list(manifest.get("requiredPaths", []))
for key in ("coreCompilerFramework", "nativeDriverFramework", "nativeRunner", "supportLibraries", "sdkPath", "clangResourceDir", "cxxStandardLibraryIncludeDir"):
    value = toolchain.get(key)
    if value:
        required.append(value)
clang_resource_dir = toolchain.get("clangResourceDir") or ""
cxx_include_dir = toolchain.get("cxxStandardLibraryIncludeDir") or ""
if clang_resource_dir:
    required.extend([
        f"{clang_resource_dir}/include/stdarg.h",
        f"{clang_resource_dir}/include/stdbool.h",
        f"{clang_resource_dir}/include/stddef.h",
    ])
if cxx_include_dir:
    required.append(f"{cxx_include_dir}/vector")
missing = []
for rel in sorted(set(required)):
    if not (root / rel).exists():
        missing.append(rel)
if missing:
    print("error: missing required BuildKit paths:")
    for rel in missing:
        print(f"- {rel}")
    raise SystemExit(1)
capabilities = set(manifest.get("capabilities") or [])
required_capabilities = {"clang-resource-dir", "cxx-stdlib-headers", "ui-framework-imports"}
missing_capabilities = sorted(required_capabilities - capabilities)
if missing_capabilities:
    print("error: BuildKit asset manifest is missing toolchain capability declarations:")
    for capability in missing_capabilities:
        print(f"- {capability}")
    raise SystemExit(1)
if not clang_resource_dir:
    print("error: BuildKit asset manifest is missing toolchain.clangResourceDir")
    raise SystemExit(1)
if not cxx_include_dir:
    print("error: BuildKit asset manifest is missing toolchain.cxxStandardLibraryIncludeDir")
    raise SystemExit(1)
if not manifest.get("swiftCompatibilityVersion"):
    print("error: BuildKit asset manifest is missing swiftCompatibilityVersion")
    raise SystemExit(1)
if not manifest.get("sdkSwiftVersion"):
    print("error: BuildKit asset manifest is missing sdkSwiftVersion")
    raise SystemExit(1)
for rel, expected in (manifest.get("sha256") or {}).items():
    path = root / rel
    if not path.is_file():
        print(f"error: hash entry is not a file: {rel}")
        raise SystemExit(1)
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    actual = h.hexdigest()
    if actual.lower() != expected.lower():
        print(f"error: sha256 mismatch for {rel}")
        print(f"expected={expected}")
        print(f"actual={actual}")
        raise SystemExit(1)
expected_native_fingerprint = os.environ.get("LITTER_BUILDKIT_EXPECT_NATIVE_SOURCE_FINGERPRINT") or ""
actual_native_fingerprint = (
    manifest.get("nativeDriverSourceFingerprint")
    or (manifest.get("source") or {}).get("nativeDriverSourceFingerprint")
    or ""
)
if expected_native_fingerprint:
    if not actual_native_fingerprint:
        print("error: BuildKit asset manifest is missing nativeDriverSourceFingerprint")
        print("Rebuild and upload the private BuildKit asset pack from the current source.")
        raise SystemExit(1)
    if actual_native_fingerprint != expected_native_fingerprint:
        print("error: BuildKit native driver source fingerprint mismatch")
        print(f"expected={expected_native_fingerprint}")
        print(f"actual={actual_native_fingerprint}")
        raise SystemExit(1)
print("BuildKit asset manifest is valid")
print(f"bundle={manifest.get('bundleIdentifier')} sdk={manifest.get('sdkVersion')} swift={manifest.get('swiftVersion')}")
print(f"swiftCompatibilityVersion={manifest.get('swiftCompatibilityVersion')} sdkSwiftVersion={manifest.get('sdkSwiftVersion')}")
print(f"clangResourceDir={clang_resource_dir}")
print(f"cxxStandardLibraryIncludeDir={cxx_include_dir}")
print(f"nativeDriverSourceFingerprint={actual_native_fingerprint or 'missing'}")
print("capabilities=" + ", ".join(manifest.get("capabilities", [])))
PYVERIFY

SUPPORT_DIR="$ASSET_ROOT/Toolchains/Nyxian/CoreCompilerSupportLibs"
if ! find "$SUPPORT_DIR" -maxdepth 1 -type f \( -name 'lib_Compiler*.dylib' -o -name 'libLLVM*.dylib' -o -name 'libllvm*.dylib' \) -print -quit | grep -q .; then
  echo "error: CoreCompilerSupportLibs does not contain compiler support dylibs" >&2
  exit 1
fi

DRIVER="$ASSET_ROOT/Toolchains/Nyxian/LitterBuildKitNative.framework/LitterBuildKitNative"
CORE="$ASSET_ROOT/Toolchains/Nyxian/CoreCompiler.framework/CoreCompiler"
if [[ ! -f "$CORE" ]]; then
  echo "error: CoreCompiler.framework is missing executable CoreCompiler" >&2
  if [[ -f "$ASSET_ROOT/Toolchains/Nyxian/CoreCompiler.framework/CoreCompiler.tbd" ]]; then
    echo "error: found CoreCompiler.tbd instead; rebuild assets from the real framework product, not EagerLinkingTBDs" >&2
  fi
  exit 1
fi
if [[ ! -f "$DRIVER" ]]; then
  echo "error: LitterBuildKitNative.framework is missing executable LitterBuildKitNative" >&2
  exit 1
fi
if [[ "$(uname -s)" = "Darwin" ]]; then
  is_macho_binary() {
    local path="$1"
    [[ -f "$path" && ! -L "$path" ]] || return 1
    /usr/bin/file "$path" 2>/dev/null | /usr/bin/grep -Eiq 'Mach-O'
  }

  verify_code_signature() {
    local binary="$1"
    is_macho_binary "$binary" || return 0
    local signature_info
    signature_info="$(/usr/bin/codesign -dv --verbose=4 "$binary" 2>&1)" || {
      echo "error: $binary is not code signed" >&2
      printf '%s\n' "$signature_info" >&2
      exit 1
    }
    if ! printf '%s\n' "$signature_info" | /usr/bin/grep -Eq 'CDHash=|CodeDirectory'; then
      echo "error: $binary is missing a code directory/CDHash" >&2
      printf '%s\n' "$signature_info" >&2
      exit 1
    fi
  }

  if [[ -f "$DRIVER" ]]; then
    verify_code_signature "$DRIVER"
    /usr/bin/lipo -info "$DRIVER"
    if ! /usr/bin/nm -gU "$DRIVER" | awk '{print $NF}' | grep -qx '_litter_buildkit_run_json'; then
      echo "error: LitterBuildKitNative.framework does not export litter_buildkit_run_json" >&2
      exit 1
    fi
    /usr/bin/otool -L "$DRIVER" | sed -n '1,30p'
    if /usr/bin/otool -L "$DRIVER" | grep -q 'CoreCompiler.framework/CoreCompiler'; then
      if ! /usr/bin/otool -l "$DRIVER" | grep -q '@loader_path/..'; then
        echo "error: in-process native driver links CoreCompiler but lacks @loader_path/.. rpath" >&2
        exit 1
      fi
    fi
  fi
  if [[ -f "$CORE" ]]; then
    verify_code_signature "$CORE"
    /usr/bin/lipo -info "$CORE"
  fi
  find "$SUPPORT_DIR" -maxdepth 1 -type f \( \
    -name 'lib_Compiler*.dylib' -o \
    -name 'libLLVM*.dylib' -o \
    -name 'libllvm*.dylib' \
  \) -print | while IFS= read -r library; do
    verify_code_signature "$library"
  done
  SDK_ROOT="$ASSET_ROOT/$(python3 - "$ASSET_ROOT/manifest.json" <<'PYSDK'
import json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
print((manifest.get("toolchain") or {}).get("sdkPath") or "")
PYSDK
)"
  if [[ -d "$SDK_ROOT" ]]; then
    sdk_compiler_dylibs="$(find "$SDK_ROOT" -type f \( \
      -name 'lib_Compiler*.dylib' -o \
      -name 'libLLVM*.dylib' -o \
      -name 'libllvm*.dylib' \
    \) -print)"
    if [[ -n "$sdk_compiler_dylibs" ]]; then
      echo "error: SDK payload contains compiler dylibs that do not keep portable code signatures in the asset ZIP" >&2
      printf '%s\n' "$sdk_compiler_dylibs" | sed -n '1,200p' >&2
      exit 1
    fi
  fi
fi
