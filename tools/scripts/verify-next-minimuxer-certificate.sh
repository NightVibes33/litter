#!/usr/bin/env bash
# Exercise retained certificate imports/exports with the unified OpenSSL graph.
set -euo pipefail
build="$1"
workspace="$build/CertificateSmoke"
mkdir -p "$workspace/Tests/CertificateSmokeTests" "$workspace/Fixtures"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=KittyStore Dependency Test/OU=TESTTEAM01/O=Local Test/C=US' \
    -keyout "$workspace/Fixtures/key.pem" -out "$workspace/Fixtures/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$workspace/Fixtures/key.pem" -in "$workspace/Fixtures/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass: -out "$workspace/Fixtures/identity.p12"
python3 - "$build" "$workspace" <<'PYPACKAGE'
from pathlib import Path
import json, sys
root, workspace=map(Path, sys.argv[1:])
(workspace / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CertificateSmoke", platforms: [.macOS(.v12)],
    dependencies: [.package(path: ''' + json.dumps(str(root / 'altsign')) + ''')],
    targets: [.testTarget(name: "CertificateSmokeTests",
        dependencies: [.product(name: "AltSign-Dynamic", package: "altsign")])]
)
''')
PYPACKAGE
cat > "$workspace/Tests/CertificateSmokeTests/CertificateRoundTripTests.swift" <<'SWIFT'
import Foundation
import XCTest
import AltSign

final class CertificateRoundTripTests: XCTestCase {
    func testRetainedCertificateImportAndExportPreservesIdentity() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["KITTY_CERTIFICATE_FIXTURE"])
        let original = try XCTUnwrap(ALTCertificate(p12Data: Data(contentsOf: URL(fileURLWithPath: path)), password: ""))
        XCTAssertFalse(try XCTUnwrap(original.privateKey).isEmpty)
        let exported = try XCTUnwrap(original.p12Data())
        let restored = try XCTUnwrap(ALTCertificate(p12Data: exported, password: ""))
        XCTAssertEqual(restored.serialNumber, original.serialNumber)
        XCTAssertEqual(restored.data, original.data)
        XCTAssertEqual(restored.privateKey, original.privateKey)
    }

    func testRetainedCertificateRejectsInvalidMaterial() {
        XCTAssertNil(ALTCertificate(p12Data: Data("invalid identity".utf8), password: ""))
    }
}
SWIFT
KITTY_CERTIFICATE_FIXTURE="$workspace/Fixtures/identity.p12" swift test --package-path "$workspace"
