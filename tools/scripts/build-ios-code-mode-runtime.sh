#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DIR="$REPO_DIR/build/rusty-v8-source"
TARGET="${1:-aarch64-apple-ios}"
OUTPUT_DIR="$REPO_DIR/build/ios-code-mode/$TARGET"
test "$(uname -s)" = Darwin
test "$(git -C "$SOURCE_DIR" rev-parse HEAD)" = 5c15a6995c9bb4bacd3e341b59fff32c909c80bf
# Building the upstream runtime requires this exact native ABI configuration.
# rusty_v8's iOS build logic disables JIT tiers and WebAssembly on device.
export V8_FROM_SOURCE=1
export LIBCLANG_PATH="$(brew --prefix llvm)/lib"
(cd "$SOURCE_DIR" && rustup target add "$TARGET" && cargo build --locked --release --target "$TARGET" --features v8_enable_sandbox)
mkdir -p "$OUTPUT_DIR"
python3 - "$SOURCE_DIR" "$OUTPUT_DIR" "$TARGET" <<'PY'
import gzip, hashlib, pathlib, shutil, sys
source, output = map(pathlib.Path, sys.argv[1:3])
target = sys.argv[3]
archives = list(source.glob(f'target/{target}/release/gn_out/obj/librusty_v8.a'))
if len(archives) != 1:
    archives = list(source.glob(f'target/{target}/release/build/v8-*/out/gn_out/obj/librusty_v8.a'))
if len(archives) != 1:
    raise SystemExit(f'Expected one built V8 archive, found {len(archives)}')
archive = archives[0]
binding = archive.parent.parent / 'src_binding.rs'
if not binding.is_file():
    raise SystemExit('Generated ABI bindings missing')
with archive.open('rb') as src, gzip.open(output / 'librusty_v8.a.gz', 'wb') as dst:
    shutil.copyfileobj(src, dst)
shutil.copyfile(binding, output / 'src_binding.rs')
files = ['librusty_v8.a.gz', 'src_binding.rs']
(output / 'SHA256SUMS').write_text(''.join(
    f'{hashlib.file_digest((output / name).open("rb"), "sha256").hexdigest()}  {name}\n'
    for name in files
))
PY
