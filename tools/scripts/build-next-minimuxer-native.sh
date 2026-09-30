#!/usr/bin/env bash
# Build dependency artifacts before migrating the app to the new async API.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v xcodebuild >/dev/null || { echo 'error: Xcode is required' >&2; exit 1; }
build="$root/build/next-minimuxer-native"
mkdir -p "$build"
checkout() {
    local name="$1" repository="$2" revision="$3"
    local source="$build/$name"
    if [[ ! -d "$source/.git" ]]; then
        git init "$source"
        git -C "$source" remote add origin "$repository"
        git -C "$source" fetch --depth 1 origin "$revision"
        git -C "$source" checkout --detach FETCH_HEAD
    fi
    [[ "$(git -C "$source" rev-parse HEAD)" == "$revision" ]] || { echo "error: $name revision differs from its pin" >&2; exit 1; }
    git -C "$source" submodule update --init --recursive
}
checkout emproxy https://github.com/SideStore/em_proxy.git 6e117e140ca7cff4ff106bdefa18147552a0e592
checkout idevice https://github.com/SideStore/idevice.git 3e55c8486b2057e40c1f74aaaa1155c82341cf76
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
for name in emproxy idevice; do
    if [[ "$name" == emproxy ]]; then
        manifest="$build/$name/Cargo.toml"; library=libem_proxy.a; headers="$build/$name/include"; product=EMProxy
        package=em_proxy
    else
        manifest="$build/$name/ffi/Cargo.toml"; library=libidevice_ffi.a; headers="$build/$name/swift/include"; product=IDevice
        package=idevice-ffi
    fi
    target_dir="$build/$name-target"
    for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
        sdk=iphonesimulator; [[ "$target" == aarch64-apple-ios ]] && sdk=iphoneos
        IPHONEOS_DEPLOYMENT_TARGET=18.0 CARGO_BUILD_JOBS=2 CARGO_INCREMENTAL=0 \
            BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --sdk "$sdk" --show-sdk-path)" \
            cargo build --manifest-path "$manifest" -p "$package" --release --locked \
            --target "$target" --target-dir "$target_dir"
    done
    if [[ "$name" == idevice ]]; then
        # cbindgen generates this header while building the pinned FFI crate.
        cp "$build/$name/ffi/idevice.h" "$headers/idevice.h"
    fi
    lipo -create "$target_dir/aarch64-apple-ios-sim/release/$library" \
        "$target_dir/x86_64-apple-ios/release/$library" -output "$build/$product-simulator.a"
    lipo "$build/$product-simulator.a" -verify_arch arm64 x86_64
    output="$build/$product.xcframework"
    rm -rf "$output"
    xcodebuild -create-xcframework \
        -library "$target_dir/aarch64-apple-ios/release/$library" -headers "$headers" \
        -library "$build/$product-simulator.a" -headers "$headers" -output "$output"
    python3 "$root/tools/scripts/verify-unicorn-deployment.py" "$output" --ios-only
done
