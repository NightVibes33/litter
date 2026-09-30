#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source="$root/ThirdParty/SideStore/Unicorn"
output="$source/../AnisetteKit/Frameworks/KittyStoreUnicorn.xcframework"
expected=a53ddc9ac6d65b24936d4a37917333fcd816cfd0
recipe="$(shasum -a 256 "${BASH_SOURCE[0]}" | cut -d' ' -f1)"
if [[ -f "$output/.litter-recipe" ]] && [[ "$(cat "$output/.litter-recipe")" == "$recipe:$expected" ]] && python3 "$root/tools/scripts/verify-unicorn-deployment.py" "$output"; then exit 0; fi
command -v xcodebuild >/dev/null || { echo 'error: Xcode is required to rebuild Unicorn' >&2; exit 1; }
git -C "$root" submodule update --init --recursive ThirdParty/SideStore/Unicorn
[[ "$(git -C "$source" rev-parse HEAD)" == "$expected" ]] || { echo 'error: unexpected Unicorn revision' >&2; exit 1; }
build="$root/build/kittystore-unicorn"
mkdir -p "$build"
# Keep the pinned checkout intact; apply the mobile configure overlay in staging.
python3 - "$source" "$build/source" <<'PYSOURCE'
from pathlib import Path
import shutil, sys
source, staged = map(Path, sys.argv[1:])
if staged.exists(): shutil.rmtree(staged)
shutil.copytree(source, staged, ignore=shutil.ignore_patterns('.git', 'docs', 'build*', '.build'))
p=staged / 'qemu/configure'
s=p.read_text(); original='  QEMU_LDFLAGS="-framework CoreFoundation -framework IOKit $QEMU_LDFLAGS"'
assert s.count(original) == 1, 'Unicorn Darwin configure overlay needs rebasing'
s=s.replace(original, '  if test "$LITTER_UNICORN_MOBILE" = "1"; then\n    QEMU_LDFLAGS="-framework CoreFoundation $QEMU_LDFLAGS"\n  else\n' + original + '\n  fi')
s=s.replace("# parse CC options first", 'cpu="${LITTER_UNICORN_CONFIGURE_CPU:-$cpu}"\n# parse CC options first', 1)
p.write_text(s)
PYSOURCE
trap 'status=$?; for log in "$build"/*/config.log; do if [[ -f "$log" ]]; then echo "Configure diagnostics: $log" >&2; tail -n 80 "$log" >&2; fi; done; exit "$status"' ERR
args=()
for slice in macos ios simulator; do
    case "$slice" in
        macos) sdk=macosx; archs='arm64;x86_64'; flags='-arch arm64 -arch x86_64'; minimum=12.0; system=Darwin; triple=x86_64-apple-macos12.0 ;;
        ios) sdk=iphoneos; archs=arm64; flags='-arch arm64'; minimum=18.0; system=iOS; triple=arm64-apple-ios18.0 ;;
        simulator) sdk=iphonesimulator; archs='arm64;x86_64'; flags='-arch arm64 -arch x86_64'; minimum=18.0; system=iOS; triple=x86_64-apple-ios18.0-simulator ;;
    esac
    mkdir -p "$build/$slice"
    # QEMU configure invokes the compiler directly, outside CMake's target flags.
    # A compiler wrapper carries the same deployment target into those probes.
    python3 - "$build/$slice/clang-target" "$(xcrun --sdk "$sdk" --find clang)" "$triple" <<'PYCOMPILER'
from pathlib import Path
import shlex, sys
p=Path(sys.argv[1]); p.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.argv[2]) + ' -target ' + shlex.quote(sys.argv[3]) + ' "$@"\n'); p.chmod(0o755)
PYCOMPILER
    mobile=1; [[ "$slice" == macos ]] && mobile=0
    configure_cpu=x86_64; [[ "$slice" == ios ]] && configure_cpu=aarch64
    LITTER_UNICORN_CONFIGURE_CPU="$configure_cpu" LITTER_UNICORN_MOBILE="$mobile" ARCHFLAGS="$flags" cmake -S "$build/source" -B "$build/$slice" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME="$system" \
        -DCMAKE_C_COMPILER="$build/$slice/clang-target" \
        -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$sdk" --show-sdk-path)" \
        -DCMAKE_OSX_ARCHITECTURES="$archs" -DCMAKE_OSX_DEPLOYMENT_TARGET="$minimum" \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DBUILD_SHARED_LIBS=OFF \
        -DUNICORN_ARCH=aarch64 -DUNICORN_ENABLE_TCI=ON \
        -DUNICORN_LEGACY_STATIC_ARCHIVE=ON -DUNICORN_BUILD_TESTS=OFF -DUNICORN_INSTALL=OFF
    if [[ "$slice" != macos ]]; then
        python3 - "$build/$slice/config-host.h" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); p.write_text(p.read_text().replace('#define HAVE_PTHREAD_JIT_PROTECT 1', '/* TCI does not use pthread JIT protection. */'))
PY
    fi
    cmake --build "$build/$slice" --parallel 3
    args+=(-library "$build/$slice/libunicorn.a" -headers "$source/include")
done
rm -rf "$output"
mkdir -p "$(dirname "$output")"
xcodebuild -create-xcframework "${args[@]}" -output "$output"
python3 "$root/tools/scripts/verify-unicorn-deployment.py" "$output"
printf '%s:%s\n' "$recipe" "$expected" > "$output/.litter-recipe"
