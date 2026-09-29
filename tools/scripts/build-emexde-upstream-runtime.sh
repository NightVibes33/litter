#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(pwd)}"
NYXIAN_ROOT="$ROOT/ThirdParty/EmexDE/Source"
OUT="$ROOT/apps/ios/GeneratedNyxianRuntime"
LOCK="$ROOT/ThirdParty/EmexDE/UPSTREAM_LOCK.json"

expected_nyxian="$(python3 - "$LOCK" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))["nyxian"]["commit"])
PY
)"
actual_nyxian="$(git -C "$NYXIAN_ROOT" rev-parse HEAD)"
if [ "$actual_nyxian" != "$expected_nyxian" ]; then
  echo "error: Nyxian checkout mismatch: expected $expected_nyxian, got $actual_nyxian" >&2
  exit 1
fi

support="$NYXIAN_ROOT/Frameworks/CoreCompiler/CoreCompilerSupportLibs"
if [ ! -s "$support/LLVM.xcframework/ios-arm64/llvm.a" ]; then
  echo "error: exact CoreCompiler support artifacts are not prepared" >&2
  exit 1
fi

echo "Building the exact upstream Nyxian app graph to produce runtime binaries"
(
  cd "$NYXIAN_ROOT"
  CHECK_DEPS=0 make compile
)

APP="$NYXIAN_ROOT/build/Nyxian.xcarchive/Products/Applications/Nyxian.app"
if [ ! -d "$APP" ]; then
  echo "error: upstream Nyxian archive did not produce $APP" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
for binary in SuperSlot.dylib libBroadpatch.dylib bootstrapd.dylib MobileDevelopmentService.dylib; do
  source_binary="$APP/Frameworks/$binary"
  if [ ! -s "$source_binary" ]; then
    echo "error: upstream Nyxian archive is missing runtime binary: $binary" >&2
    exit 1
  fi
  ditto "$source_binary" "$OUT/$binary"
done

for framework in CoreCompiler.framework MobileDevelopmentKit.framework LiveShim.framework; do
  if [ ! -d "$APP/Frameworks/$framework" ]; then
    echo "error: upstream Nyxian archive is missing framework: $framework" >&2
    exit 1
  fi
done

python3 - "$OUT/manifest.json" "$LOCK" <<'PY'
import json,sys
out,lock_path=sys.argv[1:]
lock=json.load(open(lock_path))
manifest={
  "nyxian":lock["nyxian"]["commit"],
  "llvmOnIOS":lock["llvmOnIOS"]["commit"],
  "swiftBranch":lock["llvmOnIOS"]["swiftBranch"],
  "runtimeBinaries":[
    "SuperSlot.dylib",
    "libBroadpatch.dylib",
    "bootstrapd.dylib",
    "MobileDevelopmentService.dylib",
  ],
}
with open(out,"w") as f:
    json.dump(manifest,f,indent=2,sort_keys=True)
    f.write("\n")
PY

echo "Prepared exact upstream Nyxian runtime binaries in $OUT"
