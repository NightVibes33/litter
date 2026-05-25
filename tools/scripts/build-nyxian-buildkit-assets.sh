#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYXIAN_ROOT="${NYXIAN_ROOT:-${ROOT_DIR}/ThirdParty/Nyxian}"
LLVM_ROOT="${LLVM_ON_IOS_ROOT:-${ROOT_DIR}/ThirdParty/LLVM-On-iOS}"
BUILD_UPSTREAM="${LITTER_NYXIAN_BUILD_UPSTREAM:-1}"
NYXIAN_LLVM_REF="${LITTER_NYXIAN_LLVM_REF:-swift}"
NYXIAN_LLVM_FALLBACK_REF="${LITTER_NYXIAN_LLVM_FALLBACK_REF:-swift}"
CORECOMPILER_FRAMEWORK="${CORECOMPILER_FRAMEWORK:-}"
CORECOMPILER_SUPPORT_LIBS="${CORECOMPILER_SUPPORT_LIBS:-}"
CORECOMPILER_SCHEME="${CORECOMPILER_SCHEME:-CoreCompiler}"
NATIVE_MODE="${LITTER_BUILDKIT_NATIVE_MODE:-inprocess}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: build-nyxian-buildkit-assets.sh must run on macOS with full Xcode available" >&2
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "error: xcode-select is not configured" >&2
  exit 1
fi

find_corecompiler_framework() {
  for root in "$@"; do
    [[ -e "$root" ]] || continue
    while IFS= read -r found; do
      case "$found" in
        */EagerLinkingTBDs/*)
          echo "warning: ignoring stub-only CoreCompiler framework: $found" >&2
          continue
          ;;
      esac
      if [[ -f "$found/CoreCompiler" ]]; then
        printf '%s\n' "$found"
        return 0
      fi
      if [[ -f "$found/CoreCompiler.tbd" ]]; then
        echo "warning: ignoring CoreCompiler.framework without executable: $found" >&2
      fi
    done < <(find "$root" -type d -name CoreCompiler.framework -print 2>/dev/null | sort)
  done
  return 1
}


clone_or_update_dependency() {
  local path="$1"
  local repo="$2"
  local ref="$3"
  local fallback_ref="$4"
  local marker="$5"

  if [[ -f "$path/$marker" ]]; then
    echo "==> Using existing dependency: ${path#$ROOT_DIR/}"
    return 0
  fi

  rm -rf "$path"
  mkdir -p "$(dirname "$path")"
  echo "==> Fetching ${path#$ROOT_DIR/} from $repo ($ref)"
  if git clone --depth 1 --branch "$ref" "$repo" "$path"; then
    return 0
  fi

  if [[ "$fallback_ref" != "$ref" ]]; then
    echo "warning: failed to fetch $repo ref $ref; retrying $fallback_ref" >&2
    rm -rf "$path"
    git clone --depth 1 --branch "$fallback_ref" "$repo" "$path"
    return 0
  fi

  rm -rf "$path"
  git clone --depth 1 "$repo" "$path"
}

ensure_nyxian_build_dependencies() {
  [[ -f "$NYXIAN_ROOT/.gitmodules" ]] || return 0

  clone_or_update_dependency \
    "$NYXIAN_ROOT/LLVM-On-iOS" \
    "https://github.com/ProjectNyxian/LLVM-On-iOS.git" \
    "$NYXIAN_LLVM_REF" \
    "$NYXIAN_LLVM_FALLBACK_REF" \
    "Makefile"

  if [[ "${LITTER_NYXIAN_FETCH_FULL_SUBMODULES:-0}" = "1" ]]; then
    clone_or_update_dependency \
      "$NYXIAN_ROOT/libroot" \
      "https://github.com/Opa334/libroot.git" \
      "${LITTER_NYXIAN_LIBROOT_REF:-main}" \
      "${LITTER_NYXIAN_LIBROOT_FALLBACK_REF:-master}" \
      "README.md"
    clone_or_update_dependency \
      "$NYXIAN_ROOT/TrollStore" \
      "https://github.com/opa334/TrollStore" \
      "${LITTER_NYXIAN_TROLLSTORE_REF:-main}" \
      "${LITTER_NYXIAN_TROLLSTORE_FALLBACK_REF:-master}" \
      "Makefile"
  fi
}

if [[ "$BUILD_UPSTREAM" = "1" ]]; then
  ensure_nyxian_build_dependencies
  if [[ -f "$NYXIAN_ROOT/Makefile" && -d "$NYXIAN_ROOT/LLVM-On-iOS" ]]; then
    echo "==> Building Nyxian CoreCompiler support libs"
    CHECK_DEPS="${CHECK_DEPS:-0}" make -C "$NYXIAN_ROOT" CoreCompiler/CoreCompilerSupportLibs
  elif [[ -f "$LLVM_ROOT/Makefile" && -d "$LLVM_ROOT/Scripts" ]]; then
    echo "==> Building LLVM-On-iOS support libs"
    make -C "$LLVM_ROOT" all
    mkdir -p "$NYXIAN_ROOT/CoreCompiler"
    rm -rf "$NYXIAN_ROOT/CoreCompiler/CoreCompilerSupportLibs"
    cp -R "$LLVM_ROOT/CoreCompilerSupportLibs" "$NYXIAN_ROOT/CoreCompiler/CoreCompilerSupportLibs"
    cp -R "$LLVM_ROOT/LLVM.xcframework" "$NYXIAN_ROOT/CoreCompiler/CoreCompilerSupportLibs/LLVM.xcframework"
  else
    echo "warning: full Nyxian/LLVM-On-iOS build scripts are not vendored yet; run tools/scripts/vendor-nyxian.sh first" >&2
  fi
fi

if [[ -n "$CORECOMPILER_FRAMEWORK" && ! -f "$CORECOMPILER_FRAMEWORK/CoreCompiler" ]]; then
  echo "error: CoreCompiler.framework is missing its executable: $CORECOMPILER_FRAMEWORK/CoreCompiler" >&2
  echo "       Refusing to package a stub-only framework such as CoreCompiler.tbd." >&2
  exit 1
fi
if [[ -z "$CORECOMPILER_FRAMEWORK" ]]; then
  CORECOMPILER_FRAMEWORK="$(find_corecompiler_framework "$NYXIAN_ROOT" "$ROOT_DIR/artifacts" "$ROOT_DIR/build" || true)"
fi
if [[ -z "$CORECOMPILER_FRAMEWORK" && -f "$NYXIAN_ROOT/Nyxian.xcodeproj/project.pbxproj" ]]; then
  echo "==> Building $CORECOMPILER_SCHEME framework from Nyxian.xcodeproj"
  xcodebuild \
    -project "$NYXIAN_ROOT/Nyxian.xcodeproj" \
    -scheme "$CORECOMPILER_SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$ROOT_DIR/artifacts/buildkit/DerivedData-Nyxian" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM=""
  CORECOMPILER_FRAMEWORK="$(find_corecompiler_framework "$ROOT_DIR/artifacts/buildkit/DerivedData-Nyxian" "$NYXIAN_ROOT" || true)"
fi
if [[ -z "$CORECOMPILER_FRAMEWORK" || ! -d "$CORECOMPILER_FRAMEWORK" || ! -f "$CORECOMPILER_FRAMEWORK/CoreCompiler" ]]; then
  echo "error: CoreCompiler.framework with executable CoreCompiler was not found" >&2
  echo "Set CORECOMPILER_FRAMEWORK=/path/CoreCompiler.framework or run tools/scripts/vendor-nyxian.sh on a Mac and rebuild." >&2
  exit 1
fi

if [[ -z "$CORECOMPILER_SUPPORT_LIBS" ]]; then
  for candidate in \
    "$NYXIAN_ROOT/CoreCompiler/CoreCompilerSupportLibs" \
    "$LLVM_ROOT/CoreCompilerSupportLibs" \
    "$(dirname "$CORECOMPILER_FRAMEWORK")/CoreCompilerSupportLibs"; do
    if [[ -d "$candidate" ]]; then
      CORECOMPILER_SUPPORT_LIBS="$candidate"
      break
    fi
  done
fi
if [[ -z "$CORECOMPILER_SUPPORT_LIBS" || ! -d "$CORECOMPILER_SUPPORT_LIBS" ]]; then
  echo "error: CoreCompilerSupportLibs was not found" >&2
  echo "Set CORECOMPILER_SUPPORT_LIBS=/path/CoreCompilerSupportLibs or build LLVM-On-iOS first." >&2
  exit 1
fi

export CORECOMPILER_FRAMEWORK
export CORECOMPILER_SUPPORT_LIBS
export LITTER_BUILDKIT_NATIVE_MODE="$NATIVE_MODE"

echo "==> Packaging LitterBuildKitAssets.zip ($NATIVE_MODE mode)"
"$ROOT_DIR/tools/scripts/package-buildkit-assets.sh"
"$ROOT_DIR/tools/scripts/verify-nyxian-buildkit-assets.sh" "${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}"

cat <<EOF

BuildKit asset pack complete.
ZIP: ${LITTER_BUILDKIT_ZIP:-${ROOT_DIR}/artifacts/buildkit/LitterBuildKitAssets.zip}
Upload private release:
  LITTER_BUILDKIT_ASSET_TOKEN=<token> tools/scripts/upload-buildkit-assets-release.sh
EOF
