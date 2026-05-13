#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT="${1:-${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

python3 - "$ASSET_ROOT" <<'PYVERIFY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
manifest_path = root / "manifest.json"
manifest = json.loads(manifest_path.read_text())
toolchain = manifest.get("toolchain", {})
required = list(manifest.get("requiredPaths", []))
for key in ("coreCompilerFramework", "nativeDriverFramework", "nativeRunner", "supportLibraries", "sdkPath"):
    value = toolchain.get(key)
    if value:
        required.append(value)
missing = []
for rel in sorted(set(required)):
    if not (root / rel).exists():
        missing.append(rel)
if missing:
    print("error: missing required BuildKit paths:")
    for rel in missing:
        print(f"- {rel}")
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
print("BuildKit asset manifest is valid")
print(f"bundle={manifest.get('bundleIdentifier')} sdk={manifest.get('sdkVersion')} swift={manifest.get('swiftVersion')}")
print("capabilities=" + ", ".join(manifest.get("capabilities", [])))
PYVERIFY

SUPPORT_DIR="$ASSET_ROOT/Toolchains/Nyxian/CoreCompilerSupportLibs"
if ! find "$SUPPORT_DIR" -maxdepth 1 -type f \( -name 'lib_Compiler*.dylib' -o -name 'libLLVM*.dylib' -o -name 'libllvm*.dylib' \) -print -quit | grep -q .; then
  echo "error: CoreCompilerSupportLibs does not contain compiler support dylibs" >&2
  exit 1
fi

DRIVER="$ASSET_ROOT/Toolchains/Nyxian/LitterBuildKitNative.framework/LitterBuildKitNative"
CORE="$ASSET_ROOT/Toolchains/Nyxian/CoreCompiler.framework/CoreCompiler"
if [[ "$(uname -s)" = "Darwin" ]]; then
  if [[ -f "$DRIVER" ]]; then
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
  [[ -f "$CORE" ]] && /usr/bin/lipo -info "$CORE" || true
fi
