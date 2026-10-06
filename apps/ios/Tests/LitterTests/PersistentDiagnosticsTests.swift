import XCTest
@testable import Litter

final class PersistentDiagnosticsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPreviousSessionSurvivesNewWriterAndSecretsAreRedacted() throws {
        DiagnosticsLogWriter(directory: directory).append("old-session Bearer abcdefghijklmnopqrstuvwxyz")
        DiagnosticsLogWriter(directory: directory).append("new-session")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        let content = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        XCTAssertTrue(content.contains("old-session"))
        XCTAssertTrue(content.contains("new-session"))
        XCTAssertTrue(content.contains("[REDACTED]"))
        XCTAssertFalse(content.contains("abcdefghijklmnopqrstuvwxyz"))
    }

    func testRotationBoundsDiskUsageUnderConcurrentWrites() throws {
        let writer = DiagnosticsLogWriter(directory: directory, maxBytes: 256, maxFiles: 3)
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            writer.append("line \(index) " + String(repeating: "x", count: 100))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertLessThanOrEqual(files.count, 3)
        XCTAssertFalse(files.isEmpty)
        for file in files { XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 256) }
    }

    func testRepeatedApplePayloadIsSavedOnce() throws {
        let writer = DiagnosticsLogWriter(directory: directory)
        let data = Data("crash report".utf8)
        let first = try XCTUnwrap(writer.saveReport(data, prefix: "apple-diagnostic", extension: "json"))
        XCTAssertEqual(writer.saveReport(data, prefix: "apple-diagnostic", extension: "json"), first)
        XCTAssertEqual(try Data(contentsOf: first), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }
}
