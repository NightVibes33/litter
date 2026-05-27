import XCTest
@testable import Litter

final class FeatherSigningMaterialStoreTests: XCTestCase {
    func testValidateFileExtensionAcceptsSigningInputs() throws {
        XCTAssertNoThrow(try FeatherSigningMaterialStore.validateFileExtension(
            URL(fileURLWithPath: "/tmp/identity.p12"),
            allowed: ["p12", "pfx"],
            label: "certificate"
        ))

        XCTAssertNoThrow(try FeatherSigningMaterialStore.validateFileExtension(
            URL(fileURLWithPath: "/tmp/profile.mobileprovision"),
            allowed: ["mobileprovision", "provisionprofile"],
            label: "provisioning profile"
        ))
    }

    func testValidateFileExtensionRejectsWrongSigningInput() throws {
        XCTAssertThrowsError(try FeatherSigningMaterialStore.validateFileExtension(
            URL(fileURLWithPath: "/tmp/not-a-certificate.txt"),
            allowed: ["p12", "pfx"],
            label: "certificate"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("Select a certificate file"))
        }
    }

    func testStageSelectionCopiesPickerFileForLaterRead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("identity.p12", isDirectory: false)
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try data.write(to: source)

        let staged = try FeatherSigningMaterialStore.stageSelectionForLaterRead(from: source)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }

        XCTAssertEqual(staged.lastPathComponent, "identity.p12")
        XCTAssertTrue(staged.path.contains("/FeatherSigning/StagedSelections/"))
        XCTAssertEqual(try Data(contentsOf: staged), data)
    }
}
