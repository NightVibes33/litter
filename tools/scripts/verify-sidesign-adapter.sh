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
SWIFT
swift test --package-path "$root/ThirdParty/SideStore/SideSign"
swift test --package-path "$workspace"
