#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v swift >/dev/null || { echo "error: Swift is required to verify the signing adapter" >&2; exit 127; }
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/Sources/KittyStoreSigningSmoke" "$workspace/Tests/KittyStoreSigningSmokeTests"
cp "$root/apps/ios/Sources/KittyStoreSigning/KittyStoreSideSignEngine.swift" "$workspace/Sources/KittyStoreSigningSmoke/"
python3 - "$root" "$workspace" <<'PY'
import json, pathlib, sys
root, workspace = map(pathlib.Path, sys.argv[1:])
source = json.dumps(str(root / 'ThirdParty/SideStore/SideSign'))
(workspace / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "KittyStoreSigningSmoke",
    platforms: [.macOS(.v12)],
    products: [.library(name: "KittyStoreSigningSmoke", targets: ["KittyStoreSigningSmoke"])],
    dependencies: [.package(path: ''' + source + ''')],
    targets: [
        .target(name: "KittyStoreSigningSmoke", dependencies: [.product(name: "SideSign", package: "SideSign")]),
        .testTarget(name: "KittyStoreSigningSmokeTests", dependencies: ["KittyStoreSigningSmoke"])
    ]
)
''')
PY
cat > "$workspace/Tests/KittyStoreSigningSmokeTests/SigningBoundaryTests.swift" <<'SWIFT'
import Foundation
import Testing
@testable import KittyStoreSigningSmoke

@Test func rejectsInvalidSigningMaterialWithoutCreatingOutput() async throws {
    let appURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
    do {
        try await KittyStoreSideSignEngine.sign(
            appURL: appURL, teamIdentifier: "TEST", teamName: "Test", teamType: "free",
            certificateP12: Data("invalid certificate".utf8), provisioningProfileData: []
        )
        Issue.record("Invalid signing material was accepted")
    } catch {
        #expect(!FileManager.default.fileExists(atPath: appURL.path))
    }
 }

@Test func signsDisposableLocalAppWithImportedIdentity() async throws {
    let fixture = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LITTER_SIGNING_SMOKE_FIXTURE"]))
    let appURL = fixture.appendingPathComponent("Test.app")
    let profile = try Data(contentsOf: fixture.appendingPathComponent("profile.mobileprovision"))
    let progress = Progress(totalUnitCount: 100)
    try await KittyStoreSideSignEngine.sign(
        appURL: appURL, teamIdentifier: "TESTTEAM01", teamName: "Local Test", teamType: "free",
        certificateP12: Data(contentsOf: fixture.appendingPathComponent("identity.p12")),
        provisioningProfileData: [profile], progress: progress
    )
    #expect(try Data(contentsOf: appURL.appendingPathComponent("embedded.mobileprovision")) == profile)
    #expect(progress.fractionCompleted == 1)
    #expect(FileManager.default.fileExists(atPath: appURL.appendingPathComponent("_CodeSignature/CodeResources").path))
}
SWIFT
# Use a local, disposable signing identity and app; never contact Apple's portal.
fixture="$workspace/fixture"
mkdir -p "$fixture/Test.app"
printf 'int main(void) { return 0; }\n' > "$fixture/main.c"
clang "$fixture/main.c" -o "$fixture/Test.app/Test"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=KittyStore Integration Test/OU=TESTTEAM01/O=Local Test/C=US' \
    -keyout "$fixture/key.pem" -out "$fixture/cert.pem" >/dev/null 2>&1
openssl x509 -in "$fixture/cert.pem" -outform DER -out "$fixture/cert.der"
openssl pkcs12 -export -inkey "$fixture/key.pem" -in "$fixture/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass: -out "$fixture/identity.p12"
python3 - "$fixture" <<'PYFIXTURE'
from pathlib import Path
import datetime, plistlib, sys
root = Path(sys.argv[1]); now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
(root / 'Test.app/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.example.kittystore.integration', 'CFBundleExecutable': 'Test',
    'CFBundleName': 'Test', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0'
}))
(root / 'profile.plist').write_bytes(plistlib.dumps({
    'Name': 'Local integration profile', 'UUID': '91C09561-56DC-4B36-9146-117AFB1604F6',
    'TeamIdentifier': ['TESTTEAM01'], 'TeamName': 'Local Test', 'ApplicationIdentifierPrefix': ['TESTTEAM01'],
    'CreationDate': now, 'ExpirationDate': now + datetime.timedelta(days=1), 'TimeToLive': 1,
    'Platform': ['iOS'], 'ProvisionedDevices': ['LOCAL-TEST-DEVICE'],
    'DeveloperCertificates': [(root / 'cert.der').read_bytes()],
    'Entitlements': {'application-identifier': 'TESTTEAM01.com.example.kittystore.integration',
                     'com.apple.developer.team-identifier': 'TESTTEAM01', 'get-task-allow': True}
}))
PYFIXTURE
openssl smime -sign -binary -nodetach -in "$fixture/profile.plist" \
    -signer "$fixture/cert.pem" -inkey "$fixture/key.pem" -outform DER -out "$fixture/profile.mobileprovision"
export LITTER_SIGNING_SMOKE_FIXTURE="$fixture"
swift test --package-path "$root/ThirdParty/SideStore/SideSign"
swift test --package-path "$workspace" --scratch-path "$root/ThirdParty/SideStore/SideSign/.build"
