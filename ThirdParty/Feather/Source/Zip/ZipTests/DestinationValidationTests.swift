import Foundation
import XCTest
@testable import Zip

final class DestinationValidationTests: XCTestCase {
    func testNormalEntryStaysInsideDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Zip.validatedDestination(for: "Payload/Test.app/Info.plist", in: root)
        XCTAssertTrue(result.path.hasPrefix(root.resolvingSymlinksInPath().path + "/"))
    }

    func testUnsafeDestinationNamesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for entry in ["", "/absolute", "../outside", "folder/../outside", "folder\\..\\outside", "file\0name"] {
            XCTAssertThrowsError(try Zip.validatedDestination(for: entry, in: root))
        }
    }

    func testExistingSymlinkCannotChangeDestinationBoundary() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = temp.appendingPathComponent("destination")
        let outside = temp.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try Zip.validatedDestination(for: "link/file", in: root))
    }
}
