#!/usr/bin/env bash
# Build the Android proot executable used by the local Alpine terminal backend.
#
# Android only extracts native payloads named lib*.so, so the PIE executable and
# the unbundled proot loader are installed under app/src/main/jniLibs/<abi>/ and
# executed directly by Rust from applicationInfo.nativeLibraryDir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_DIR/apps/android/app/src/main/jniLibs"
ASSETS_DIR="$REPO_DIR/apps/android/app/src/main/assets"
BUILD_DIR="${PROOT_ANDROID_BUILD_DIR:-$REPO_DIR/apps/android/build/proot}"

ANDROID_ABIS="${ANDROID_ABIS:-arm64-v8a}"
ANDROID_API="${ANDROID_API:-26}"
PROOT_COMMIT="${PROOT_COMMIT:-ee10b279a38d34b6704345bc448d18f019ca1b49}"
PROOT_SOURCE_SHA256="${PROOT_SOURCE_SHA256:-9f2cc32e60be6c2a09bade03f98e22bb27ccecda926c8a74979df03ae755b1dd}"
TALLOC_VERSION="${TALLOC_VERSION:-2.4.3}"
TALLOC_SOURCE_SHA256="${TALLOC_SOURCE_SHA256:-dc46c40b9f46bb34dd97fe41f548b0e8b247b77a918576733c528e83abd854dd}"

die() {
    echo "error: $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

need curl
need make
need shasum
need unzip

NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$NDK_HOME" ]]; then
    die "set ANDROID_NDK_HOME or ANDROID_NDK_ROOT"
fi

HOST_TAG=""
for candidate in darwin-x86_64 darwin-aarch64 linux-x86_64; do
    if [[ -d "$NDK_HOME/toolchains/llvm/prebuilt/$candidate" ]]; then
        HOST_TAG="$candidate"
        break
    fi
done
[[ -n "$HOST_TAG" ]] || die "could not find an LLVM prebuilt toolchain under $NDK_HOME"

TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
for tool in llvm-ar llvm-objcopy llvm-objdump llvm-ranlib llvm-readelf llvm-strip; do
    [[ -x "$TOOLCHAIN/bin/$tool" ]] || die "missing NDK tool: $TOOLCHAIN/bin/$tool"
done

JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"
mkdir -p "$BUILD_DIR/downloads" "$BUILD_DIR/bin"
ln -sf "$TOOLCHAIN/bin/llvm-readelf" "$BUILD_DIR/bin/readelf"

fetch_checked() {
    local url="$1"
    local sha="$2"
    local out="$3"
    if [[ ! -f "$out" ]]; then
        echo "==> Downloading $(basename "$out")"
        curl -fsSL --retry 3 -o "$out" "$url"
    fi
    echo "$sha  $out" | shasum -a 256 -c -
}

extract_once() {
    local archive="$1"
    local marker="$2"
    local dest="$3"
    if [[ -f "$marker" ]]; then
        return
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    case "$archive" in
        *.zip) unzip -q "$archive" -d "$dest" ;;
        *.tar.gz | *.tgz) tar -xzf "$archive" -C "$dest" ;;
        *) die "unsupported archive: $archive" ;;
    esac
    touch "$marker"
}

target_for_abi() {
    case "$1" in
        arm64-v8a) echo "aarch64-linux-android" ;;
        x86_64) echo "x86_64-linux-android" ;;
        *) die "unsupported Android ABI '$1' (supported: arm64-v8a, x86_64)" ;;
    esac
}

fetch_sources() {
    local proot_zip="$BUILD_DIR/downloads/proot-$PROOT_COMMIT.zip"
    local talloc_tgz="$BUILD_DIR/downloads/talloc-$TALLOC_VERSION.tar.gz"

    fetch_checked \
        "https://github.com/termux/proot/archive/$PROOT_COMMIT.zip" \
        "$PROOT_SOURCE_SHA256" \
        "$proot_zip"
    fetch_checked \
        "https://www.samba.org/ftp/talloc/talloc-$TALLOC_VERSION.tar.gz" \
        "$TALLOC_SOURCE_SHA256" \
        "$talloc_tgz"

    extract_once "$proot_zip" "$BUILD_DIR/proot-$PROOT_COMMIT.extracted" "$BUILD_DIR/proot-src"
    extract_once "$talloc_tgz" "$BUILD_DIR/talloc-$TALLOC_VERSION.extracted" "$BUILD_DIR/talloc-src"
}

write_talloc_cross_answers() {
    local path="$1"
    cat > "$path" <<'EOF'
Checking uname sysname type: "Linux"
Checking uname machine type: "dontcare"
Checking uname release type: "dontcare"
Checking uname version type: "dontcare"
Checking simple C program: OK
building library support: OK
Checking for large file support: OK
Checking for -D_FILE_OFFSET_BITS=64: OK
Checking for WORDS_BIGENDIAN: OK
Checking for C99 vsnprintf: OK
Checking for HAVE_SECURE_MKSTEMP: OK
rpath library support: OK
-Wl,--version-script support: FAIL
Checking correct behavior of strtoll: OK
Checking correct behavior of strptime: OK
Checking for HAVE_IFACE_GETIFADDRS: OK
Checking for HAVE_IFACE_IFCONF: OK
Checking for HAVE_IFACE_IFREQ: OK
Checking getconf LFS_CFLAGS: OK
Checking for large file support without additional flags: OK
Checking for working strptime: OK
Checking for HAVE_SHARED_MMAP: OK
Checking for HAVE_MREMAP: OK
Checking for HAVE_INCOHERENT_MMAP: OK
Checking getconf large file support flags work: OK
EOF
}

build_talloc() {
    local abi="$1"
    local target="$2"
    local cc="$target$ANDROID_API-clang"
    local prefix="$BUILD_DIR/prefix/$abi"
    local src="$BUILD_DIR/build/talloc-$abi"

    if [[ -f "$prefix/lib/libtalloc.a" ]]; then
        return
    fi

    echo "==> Building talloc $TALLOC_VERSION for $abi"
    rm -rf "$src" "$prefix"
    mkdir -p "$src" "$prefix"
    cp -R "$BUILD_DIR/talloc-src/talloc-$TALLOC_VERSION/." "$src/"
    write_talloc_cross_answers "$src/cross-answers.txt"

    (
        cd "$src"
        PATH="$TOOLCHAIN/bin:$PATH" \
        CC="$cc" \
        AR="$TOOLCHAIN/bin/llvm-ar" \
        RANLIB="$TOOLCHAIN/bin/llvm-ranlib" \
        ./configure \
            --prefix="$prefix" \
            --disable-rpath \
            --disable-python \
            --cross-compile \
            --cross-answers=cross-answers.txt
        PATH="$TOOLCHAIN/bin:$PATH" make -j"$JOBS"
        PATH="$TOOLCHAIN/bin:$PATH" make install
        cd bin/default
        "$TOOLCHAIN/bin/llvm-ar" rcu "$prefix/lib/libtalloc.a" talloc*.o lib/replace/*.o
        "$TOOLCHAIN/bin/llvm-ranlib" "$prefix/lib/libtalloc.a"
    )
}

patch_proot_source() {
    local src="$1"
    local ashmem="$src/src/extension/ashmem_memfd/ashmem_memfd.c"
    if ! grep -q '#include <string.h>' "$ashmem"; then
        perl -0pi -e 's/#include <stdlib.h>\n/#include <stdlib.h>\n#include <string.h>\n/' "$ashmem"
    fi
}

build_proot() {
    local abi="$1"
    local target="$2"
    local cc="$target$ANDROID_API-clang"
    local prefix="$BUILD_DIR/prefix/$abi"
    local src="$BUILD_DIR/build/proot-$abi"
    local out_dir="$OUT_DIR/$abi"
    local out="$out_dir/libproot.so"
    local loader_out="$out_dir/libproot_loader.so"

    echo "==> Building proot $PROOT_COMMIT for $abi"
    rm -rf "$src"
    mkdir -p "$src" "$out_dir"
    cp -R "$BUILD_DIR/proot-src/proot-$PROOT_COMMIT/." "$src/"
    patch_proot_source "$src"

    (
        cd "$src/src"
        PATH="$BUILD_DIR/bin:$TOOLCHAIN/bin:$PATH" \
        make -j"$JOBS" \
            V="${V:-0}" \
            CC="$cc" \
            LD="$cc" \
            STRIP="$TOOLCHAIN/bin/llvm-strip" \
            OBJCOPY="$TOOLCHAIN/bin/llvm-objcopy" \
            OBJDUMP="$TOOLCHAIN/bin/llvm-objdump" \
            CPPFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -DARG_MAX=131072 -I. -I$prefix/include" \
            CFLAGS="-Wall -Wextra -O2 -fPIE -DPROOT_UNBUNDLE_LOADER=\\\"/__litter_proot_loader\\\"" \
            LDFLAGS="$prefix/lib/libtalloc.a -pie -Wl,-z,noexecstack" \
            PROOT_UNBUNDLE_LOADER="/__litter_proot_loader" \
            proot
        "$TOOLCHAIN/bin/llvm-strip" --strip-unneeded proot
        "$TOOLCHAIN/bin/llvm-strip" --strip-unneeded loader/loader
        cp proot "$out"
        cp loader/loader "$loader_out"
        chmod 0755 "$out"
        chmod 0755 "$loader_out"
    )

    if "$TOOLCHAIN/bin/llvm-readelf" -d "$out" | grep -q 'libtalloc'; then
        die "$out still has a dynamic libtalloc dependency"
    fi
    echo "    installed $out"
    echo "    installed $loader_out"
}

install_license_assets() {
    local proot_src="$BUILD_DIR/proot-src/proot-$PROOT_COMMIT"
    local talloc_src="$BUILD_DIR/talloc-src/talloc-$TALLOC_VERSION"
    mkdir -p "$ASSETS_DIR/licenses"
    cp "$proot_src/COPYING" "$ASSETS_DIR/licenses/proot-COPYING.txt"
    if [[ -f "$talloc_src/COPYING" ]]; then
        cp "$talloc_src/COPYING" "$ASSETS_DIR/licenses/talloc-COPYING.txt"
    elif [[ -f "$talloc_src/LICENSE" ]]; then
        cp "$talloc_src/LICENSE" "$ASSETS_DIR/licenses/talloc-COPYING.txt"
    fi
    {
        printf 'proot_commit=%s\n' "$PROOT_COMMIT"
        printf 'talloc_version=%s\n' "$TALLOC_VERSION"
        printf 'android_api=%s\n' "$ANDROID_API"
        printf 'abis=%s\n' "$ANDROID_ABIS"
    } > "$ASSETS_DIR/proot.version"
}

fetch_sources

ABI_INPUT="${ANDROID_ABIS//,/ }"
read -r -a REQUESTED_ABIS <<<"$ABI_INPUT"
if [[ "${#REQUESTED_ABIS[@]}" -eq 0 ]]; then
    REQUESTED_ABIS=(arm64-v8a)
fi

SELECTED_ABIS=""
for abi in "${REQUESTED_ABIS[@]}"; do
    target="$(target_for_abi "$abi")"
    if [[ " $SELECTED_ABIS " == *" $abi "* ]]; then
        continue
    fi
    SELECTED_ABIS="$SELECTED_ABIS $abi"
    build_talloc "$abi" "$target"
    build_proot "$abi" "$target"
done

for stale in arm64-v8a x86_64; do
    if [[ " $SELECTED_ABIS " != *" $stale "* ]]; then
        rm -f "$OUT_DIR/$stale/libproot.so" "$OUT_DIR/$stale/libproot_loader.so"
    fi
done

install_license_assets

echo
echo "Android proot artifacts installed:"
find "$OUT_DIR" \( -name 'libproot.so' -o -name 'libproot_loader.so' \) -print | sort | xargs -r ls -lh
