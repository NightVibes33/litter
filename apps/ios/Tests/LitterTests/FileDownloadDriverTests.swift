import Foundation
import XCTest
@testable import Litter

final class FileDownloadDriverTests: XCTestCase {
    func testCancellationBeforeStartDoesNotCreateAnActiveDownload() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let driver = FileDownloadDriver(destination: target, progressHandler: { _, _ in
            XCTFail("A cancelled download must not report progress")
        })
        driver.cancel()
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.invalid/cancelled")))
        do {
            _ = try await driver.start(request: request)
            XCTFail("Cancellation must be preserved before start")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        }
    }
}
