#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${EMEXDE_CORECOMPILER_RELEASE_TAG:-emexde-corecompiler}"
REPO="${GITHUB_REPOSITORY:-NightVibes33/litter}"
ROOT="${ROOT:-$(pwd)}"
CORECOMPILER_ROOT="$ROOT/ThirdParty/EmexDE/Source/CoreCompiler"
DEST="$CORECOMPILER_ROOT/CoreCompilerSupportLibs"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$CORECOMPILER_ROOT"
rm -rf "$DEST"

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer $GITHUB_TOKEN")
elif [ -n "${GH_TOKEN:-}" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer $GH_TOKEN")
fi

RELEASE_JSON="$TMP_DIR/release.json"
curl -fL --retry 3 --retry-delay 5 --max-time 120 \
  "${AUTH_HEADER[@]}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG" \
  -o "$RELEASE_JSON"

python3 - "$RELEASE_JSON" "$TMP_DIR" <<'PY_INNER'
import json
import pathlib
import sys

release_json = pathlib.Path(sys.argv[1])
out_dir = pathlib.Path(sys.argv[2])
release = json.loads(release_json.read_text())
required = {"CoreCompilerSupportLibs.tar.xz", "LLVM.xcframework.tar.xz"}
assets = {asset.get("name"): asset for asset in release.get("assets", [])}
missing = sorted(required - set(assets))
if missing:
    raise SystemExit("missing release assets: " + ", ".join(missing))
for name in sorted(required):
    asset = assets[name]
    (out_dir / f"{name}.asset-url").write_text(asset["url"])
PY_INNER

for name in CoreCompilerSupportLibs.tar.xz LLVM.xcframework.tar.xz; do
  asset_url="$(cat "$TMP_DIR/$name.asset-url")"
  curl -fL --retry 3 --retry-delay 5 --max-time 300 \
    "${AUTH_HEADER[@]}" \
    -H "Accept: application/octet-stream" \
    "$asset_url" \
    -o "$TMP_DIR/$name"
done

tar -xJf "$TMP_DIR/CoreCompilerSupportLibs.tar.xz" -C "$CORECOMPILER_ROOT"
tar -xJf "$TMP_DIR/LLVM.xcframework.tar.xz" -C "$DEST"

SUPPORT="$DEST"
LLVM_ROOT="$DEST/LLVM.xcframework/ios-arm64"
LLVM_HEADERS="$LLVM_ROOT/Headers"
SWIFT_BRANCH="${EMEXDE_SWIFT_BRANCH:-swift-6.0.3-RELEASE}"
SWIFT_LLVM_BRANCH="${EMEXDE_SWIFT_LLVM_BRANCH:-$SWIFT_BRANCH}"
SWIFT_HEADER_MARKER="$LLVM_HEADERS/swift/.emexde-swift-header-branch"

install_swift_headers() {
  if [ -f "$LLVM_HEADERS/swift/Basic/InitializeSwiftModules.h" ]; then
    if [ -f "$SWIFT_HEADER_MARKER" ] && [ "$(cat "$SWIFT_HEADER_MARKER")" = "$SWIFT_BRANCH" ] && ! grep -q 'getTrailingObjects(NumArgs)' "$LLVM_HEADERS/swift/AST/Identifier.h"; then
      return 0
    fi
    echo "Refreshing Swift compiler headers for $SWIFT_BRANCH"
    rm -rf "$LLVM_HEADERS/swift" "$LLVM_HEADERS/SwiftShims"
  else
    echo "Swift compiler headers are missing from LLVM.xcframework; fetching $SWIFT_BRANCH headers"
  fi

  swift_archive="$TMP_DIR/swift-$SWIFT_BRANCH.tar.gz"
  swift_source="$TMP_DIR/swift-source"
  mkdir -p "$swift_source"
  curl -fL --retry 3 --retry-delay 5 --max-time 300 \
    "https://github.com/swiftlang/swift/archive/refs/tags/$SWIFT_BRANCH.tar.gz" \
    -o "$swift_archive"

  archive_root="$(tar -tzf "$swift_archive" | sed -n '1s#/.*##p')"
  if [ -z "$archive_root" ]; then
    echo "error: could not determine Swift source archive root" >&2
    exit 1
  fi

  tar -xzf "$swift_archive" -C "$swift_source" --strip-components 1 \
    "$archive_root/include" \
    "$archive_root/stdlib/public/SwiftShims"
  cp -R "$swift_source/include/." "$LLVM_HEADERS/"
  cp -R "$swift_source/stdlib/public/SwiftShims/." "$LLVM_HEADERS/"
  rm -f "$LLVM_HEADERS/module.modulemap"
  cat > "$LLVM_HEADERS/swift/Config.h" <<'CONFIG_H'
#ifndef SWIFT_CONFIG_H
#define SWIFT_CONFIG_H

#define HAVE_WAIT4 1
#define HAVE_PROC_PID_RUSAGE 1
#define SWIFT_IMPLICIT_CONCURRENCY_IMPORT 1
#define SWIFT_ENABLE_EXPERIMENTAL_DISTRIBUTED 0
#define SWIFT_ENABLE_GLOBAL_ISEL_ARM64 0
#define SWIFT_ENABLE_EXPERIMENTAL_PARSER_VALIDATION 0

#endif // SWIFT_CONFIG_H
CONFIG_H
  echo "$SWIFT_BRANCH" > "$SWIFT_HEADER_MARKER"
}

install_swift_llvm_header_overlay() {
  swift_llvm_headers=(
    clang/CAS/CASOptions.h
    llvm/CAS/ActionCache.h
    llvm/CAS/CASID.h
    llvm/CAS/CASReference.h
    llvm/CAS/ObjectStore.h
    llvm/CAS/TreeEntry.h
    llvm/Support/HashingOutputBackend.h
    llvm/Support/VirtualOutputBackend.h
    llvm/Support/VirtualOutputBackends.h
    llvm/Support/VirtualOutputConfig.def
    llvm/Support/VirtualOutputConfig.h
    llvm/Support/VirtualOutputError.h
    llvm/Support/VirtualOutputFile.h
  )

  for header in "${swift_llvm_headers[@]}"; do
    destination="$LLVM_HEADERS/$header"
    [ -f "$destination" ] && continue
    case "$header" in
      clang/*) source_path="clang/include/$header" ;;
      llvm/*) source_path="llvm/include/$header" ;;
      *)
        echo "error: unsupported Swift LLVM overlay header path: $header" >&2
        exit 1
        ;;
    esac
    mkdir -p "$(dirname "$destination")"
    curl -fL --retry 3 --retry-delay 5 --max-time 120 \
      "https://raw.githubusercontent.com/swiftlang/llvm-project/$SWIFT_LLVM_BRANCH/$source_path" \
      -o "$destination"
  done
}

generate_swift_build_headers() {
  mkdir -p "$LLVM_HEADERS/swift/Option" "$LLVM_HEADERS/swift/Runtime" "$LLVM_HEADERS/lld/Common"
  python3 - "$LLVM_HEADERS/swift/Option/Options.td" "$LLVM_HEADERS/swift/Option/Options.inc" <<'PY_OPTIONS'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
ids = []
seen = set()
for line in source.read_text().splitlines():
    match = re.match(r"\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*:", line)
    if not match:
        continue
    identifier = match.group(1)
    if identifier in seen:
        continue
    seen.add(identifier)
    ids.append(identifier)
with destination.open("w") as out:
    out.write("/* Generated by Litter's emexDE CoreCompiler artifact prep. */\n")
    for identifier in ids:
        out.write(f"OPTION(_, _, {identifier}, _, _, _, _, _, _, _, _, _)\n")
PY_OPTIONS
  cat > "$LLVM_HEADERS/swift/Runtime/CMakeConfig.h" <<'RUNTIME_CONFIG_H'
#ifndef SWIFT_RUNTIME_CMAKECONFIG_H
#define SWIFT_RUNTIME_CMAKECONFIG_H

#define SWIFT_BNI_OS_BUILD 0
#define SWIFT_BNI_XCODE_BUILD 0
#define SWIFT_VERSION_MAJOR "6"
#define SWIFT_VERSION_MINOR "0"

#endif // SWIFT_RUNTIME_CMAKECONFIG_H
RUNTIME_CONFIG_H
  cat > "$LLVM_HEADERS/lld/Common/Version.inc" <<'LLD_VERSION_INC'
#define LLD_VERSION 19.1.7
#define LLD_VERSION_STRING "19.1.7"
#define LLD_VERSION_MAJOR 19
#define LLD_VERSION_MINOR 1
#define LLD_VERSION_PATCHLEVEL 7
LLD_VERSION_INC
}

install_swift_header_compatibility() {
  mkdir -p "$LLVM_HEADERS/clang/Basic"
  cat > "$LLVM_HEADERS/clang/Basic/PathRemapper.h" <<'PATH_REMAPPER_H'
#ifndef LLVM_CLANG_BASIC_PATHREMAPPER_H
#define LLVM_CLANG_BASIC_PATHREMAPPER_H

#include "clang/Basic/LLVM.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/Path.h"

#include <string>
#include <utility>

namespace clang {

class PathRemapper {
  SmallVector<std::pair<std::string, std::string>, 2> PathMappings;

public:
  void addMapping(StringRef FromPrefix, StringRef ToPrefix) {
    PathMappings.emplace_back(FromPrefix.str(), ToPrefix.str());
  }

  std::string remapPath(StringRef Path) const {
    for (const auto &Mapping : PathMappings) {
      if (Path.starts_with(Mapping.first)) {
        return (Twine(Mapping.second) + Path.substr(Mapping.first.size())).str();
      }
    }
    return Path.str();
  }

  void remapPath(SmallVectorImpl<char> &PathBuf) const {
    for (const auto &Mapping : PathMappings) {
      if (llvm::sys::path::replace_path_prefix(PathBuf, Mapping.first, Mapping.second)) {
        break;
      }
    }
  }

  bool empty() const {
    return PathMappings.empty();
  }

  ArrayRef<std::pair<std::string, std::string>> getMappings() const {
    return PathMappings;
  }
};

} // namespace clang

#endif // LLVM_CLANG_BASIC_PATHREMAPPER_H
PATH_REMAPPER_H
}

if ! find "$SUPPORT" -maxdepth 1 -type f -name 'lib_Compiler*.dylib' -print -quit | grep -q .; then
  echo "error: missing CoreCompiler support dylibs in $SUPPORT" >&2
  exit 1
fi
if [ ! -f "$LLVM_ROOT/llvm.a" ]; then
  echo "error: missing LLVM static library at $LLVM_ROOT/llvm.a" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/llvm/Support/Threading.h" ]; then
  echo "error: missing LLVM headers in $LLVM_HEADERS" >&2
  exit 1
fi
install_swift_headers
install_swift_llvm_header_overlay
generate_swift_build_headers
install_swift_header_compatibility
if [ ! -f "$LLVM_HEADERS/swift/Basic/InitializeSwiftModules.h" ]; then
  echo "error: missing Swift compiler header at $LLVM_HEADERS/swift/Basic/InitializeSwiftModules.h" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/swift/FrontendTool/FrontendTool.h" ]; then
  echo "error: missing Swift frontend header at $LLVM_HEADERS/swift/FrontendTool/FrontendTool.h" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/swift/Config.h" ]; then
  echo "error: missing generated Swift config header at $LLVM_HEADERS/swift/Config.h" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/clang/Basic/PathRemapper.h" ]; then
  echo "error: missing Clang PathRemapper compatibility header at $LLVM_HEADERS/clang/Basic/PathRemapper.h" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/clang/CAS/CASOptions.h" ]; then
  echo "error: missing Swift LLVM CAS compatibility header at $LLVM_HEADERS/clang/CAS/CASOptions.h" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/llvm/Support/VirtualOutputBackend.h" ]; then
  echo "error: missing Swift LLVM virtual output compatibility header at $LLVM_HEADERS/llvm/Support/VirtualOutputBackend.h" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/swift/Option/Options.inc" ]; then
  echo "error: missing generated Swift option header at $LLVM_HEADERS/swift/Option/Options.inc" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/swift/Runtime/CMakeConfig.h" ]; then
  echo "error: missing generated Swift runtime config header at $LLVM_HEADERS/swift/Runtime/CMakeConfig.h" >&2
  exit 1
fi
if [ ! -f "$LLVM_HEADERS/lld/Common/Version.inc" ]; then
  echo "error: missing generated LLD version header at $LLVM_HEADERS/lld/Common/Version.inc" >&2
  exit 1
fi
if [ ! -f "$SWIFT_HEADER_MARKER" ] || [ "$(cat "$SWIFT_HEADER_MARKER")" != "$SWIFT_BRANCH" ]; then
  echo "error: Swift compiler header marker does not match $SWIFT_BRANCH" >&2
  exit 1
fi
if grep -q 'getTrailingObjects(NumArgs)' "$LLVM_HEADERS/swift/AST/Identifier.h"; then
  echo "error: Swift compiler headers are not compatible with vendored LLVM 19 TrailingObjects API" >&2
  exit 1
fi
if [ -f "$LLVM_HEADERS/module.modulemap" ]; then
  echo "error: Swift root module map conflicts with Xcode public header copy at $LLVM_HEADERS/module.modulemap" >&2
  exit 1
fi

normalize_dylib() {
  dylib="$1"
  if command -v install_name_tool >/dev/null 2>&1; then
    base="$(basename "$dylib")"
    install_name_tool -id "@rpath/$base" "$dylib" 2>/dev/null || true
    install_name_tool -add_rpath '@loader_path' "$dylib" 2>/dev/null || true
    if command -v otool >/dev/null 2>&1; then
      otool -L "$dylib" | awk 'NR > 1 { print $1 }' | while IFS= read -r dependency; do
        dep_base="$(basename "$dependency")"
        case "$dep_base" in
          lib_Compiler*.dylib|libLLVM*.dylib|libllvm*.dylib)
            [ "$dependency" = "@rpath/$dep_base" ] || install_name_tool -change "$dependency" "@rpath/$dep_base" "$dylib" 2>/dev/null || true
            ;;
        esac
      done
    fi
  fi
}

find "$SUPPORT" -maxdepth 1 -type f -name '*.dylib' -print | while IFS= read -r dylib; do
  normalize_dylib "$dylib"
done

echo "Prepared emexDE CoreCompiler support artifacts in $DEST"
