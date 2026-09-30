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

python3 - "$build" <<'PYPROVENANCE'
from pathlib import Path
import hashlib, json, shutil, subprocess, sys
root=Path(sys.argv[1]); sources={}
licenses=root / 'licenses'; licenses.mkdir(exist_ok=True)
for name, license_name in [('emproxy', 'LICENSE'), ('idevice', 'LICENSE.txt')]:
    source=root / name
    sources[name]={'revision': subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
                   'cargoLockSha256': hashlib.sha256((source / 'Cargo.lock').read_bytes()).hexdigest()}
    shutil.copyfile(source / license_name, licenses / (name + '.LICENSE'))
record={'sources': sources, 'deploymentTarget': '18.0', 'simulatorArchitectures': ['arm64', 'x86_64'],
        'rustc': subprocess.check_output(['rustc', '--version'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip()}
(root / 'BUILD_PROVENANCE.json').write_text(json.dumps(record, indent=2) + '\n')
PYPROVENANCE

# Compile the complete new package graph in isolation before changing the app.
checkout minimuxer https://github.com/SideStore/minimuxer.git 12be70dc2627307a16bfd2dc7a009080d5bec909
python3 - "$build" <<'PYSTAGE'
from pathlib import Path
import json, re, shutil, sys
root=Path(sys.argv[1]); package=root / 'minimuxer'
for name, destination in [('EMProxy', package / 'Binaries'), ('IDevice', package / 'DeviceGateway/Binaries')]:
    destination.mkdir(parents=True, exist_ok=True)
    output=destination / (name + '.xcframework')
    if output.exists(): shutil.rmtree(output)
    shutil.copytree(root / (name + '.xcframework'), output)
for manifest, name in [(package / 'Package.swift', 'EMProxy'), (package / 'DeviceGateway/Package.swift', 'IDevice')]:
    text=manifest.read_text()
    pattern=r'\.binaryTarget\(\s*name:\s*"' + name + r'",\s*url:\s*"[^"\n]+",\s*checksum:\s*"[0-9a-f]+"\s*\)'
    replacement='.binaryTarget(name: "' + name + '", path: "Binaries/' + name + '.xcframework")'
    text, count=re.subn(pattern, lambda _:replacement, text)
    assert count == 1 or replacement in text, 'Missing expected ' + name + ' requirement'
    if name == 'EMProxy':
        text=text.replace('.upToNextMajor(from: "0.9.0")', 'exact: "0.9.20"')
    else:
        text=text.replace('branch: "main"', 'revision: "e3f70d16c0c551540a533a39d540e78e5b0a60a8"')
    manifest.write_text(text)
smoke=root / 'Smoke'; smoke.mkdir(exist_ok=True)
(smoke / 'Smoke.swift').write_text('import Minimuxer\npublic enum NextMinimuxerSmoke {\n    public static func makeTransport() -> Minimuxer { Minimuxer.shared }\n}\n')
(smoke / 'project.yml').write_text("""name: NextMinimuxerSmoke
options:
  deploymentTarget:
    iOS: "18.0"
packages:
  NextMinimuxer:
    path: """ + json.dumps(str(package)) + """
targets:
  NextMinimuxerSmoke:
    type: framework
    platform: iOS
    sources:
      - path: Smoke.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.kittystore.minimuxer-smoke
        GENERATE_INFOPLIST_FILE: YES
        SWIFT_VERSION: "6.0"
        CODE_SIGNING_ALLOWED: NO
    dependencies:
      - package: NextMinimuxer
        product: Minimuxer
""")
PYSTAGE
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --spec "$build/Smoke/project.yml" --project "$build/Smoke"
xcodebuild -project "$build/Smoke/NextMinimuxerSmoke.xcodeproj" -scheme NextMinimuxerSmoke \
    -destination 'generic/platform=iOS' -derivedDataPath "$build/SmokeDerivedData" \
    CODE_SIGNING_ALLOWED=NO build

# Retained account/certificate models and the new transport must share one
# OpenSSL module. Validate that combined graph separately from the app.
checkout altsign https://github.com/SideStore/AltSign.git 7efe511440cfdbddc04a723490def86232c42f6c
checkout remotepairingkit https://github.com/mahee96/RemotePairingKit.git e3f70d16c0c551540a533a39d540e78e5b0a60a8
python3 "$root/tools/scripts/stage-next-minimuxer-openssl.py" "$build"
python3 - "$build" <<'PYCOMBINED'
from pathlib import Path
import json, sys
root=Path(sys.argv[1]); smoke=root / 'Smoke'
source=smoke / 'Smoke.swift'
source.write_text('import AltSign\n' + source.read_text() + '\npublic func retainedCertificateType() -> ALTCertificate.Type { ALTCertificate.self }\n')
manifest=smoke / 'project.yml'
text=manifest.read_text().replace('targets:\n', '  RetainedAltSign:\n    path: ' + json.dumps(str(root / 'altsign')) + '\ntargets:\n')
text += '      - package: RetainedAltSign\n        product: AltSign-Dynamic\n'
manifest.write_text(text)
PYCOMBINED
xcodegen generate --spec "$build/Smoke/project.yml" --project "$build/Smoke"
xcodebuild -project "$build/Smoke/NextMinimuxerSmoke.xcodeproj" -scheme NextMinimuxerSmoke \
    -destination 'generic/platform=iOS' -derivedDataPath "$build/CombinedDerivedData" \
    CODE_SIGNING_ALLOWED=NO build
python3 - "$build/CombinedDerivedData/SourcePackages/checkouts" <<'PYLOCK'
from pathlib import Path
import subprocess, sys
checkouts=Path(sys.argv[1])
openssl=[path for path in checkouts.iterdir() if path.name.casefold() == 'openssl']
assert len(openssl) == 1, 'Expected one OpenSSL package checkout'
revision=subprocess.check_output(['git', '-C', str(openssl[0]), 'rev-parse', 'HEAD'], text=True).strip()
assert revision == 'fdc9231384f37f053dffe058fd6dfc6c5072dae5', 'Compiled OpenSSL revision differs from the 3.6.2000 pin'
print('Combined account/transport graph uses verified OpenSSL 3.6.2000 pin')
PYLOCK
bash "$root/tools/scripts/verify-next-minimuxer-certificate.sh" "$build"
