import XCTest
@testable import Litter

@MainActor
final class StreamingRendererCoordinatorTests: XCTestCase {
    func testChunksAreAppendedExactlyOnce() {
        let coordinator = StreamingRendererCoordinator()
        let renderer = coordinator.renderer(for: "message", currentText: "The SDK is installed. ")
        let chunks = ["Let the device libraries ", "finish installing; ", "signing also ",
                      "needs a secure password input."]
        for chunk in chunks { coordinator.appendDelta(chunk, for: "message") }
        coordinator.finishActive()
        XCTAssertEqual(renderer.rawText, "The SDK is installed. " + chunks.joined())
    }

    func testRendererCreatedBeforeFirstPaintIncludesUnflushedSnapshotPrefix() {
        let coordinator = StreamingRendererCoordinator()
        coordinator.appendDelta(" finish installing", for: "message", seedText: "Let the device libraries")
        // The view's snapshot is still behind the incoming stream.
        let renderer = coordinator.renderer(for: "message", currentText: "Let the device")
        coordinator.finishActive()
        XCTAssertEqual(renderer.rawText, "Let the device libraries finish installing")
    }

    func testUnknownBaselineIsSeededFromSnapshotWithoutReplayingOldChunks() {
        let coordinator = StreamingRendererCoordinator()
        coordinator.appendDelta(" libraries", for: "message")
        let renderer = coordinator.renderer(for: "message", currentText: "device libraries")
        coordinator.finishActive()
        XCTAssertEqual(renderer.rawText, "device libraries")
    }

    func testLegitimateRepeatedWordsAndUnicodeArePreserved() {
        let coordinator = StreamingRendererCoordinator()
        let renderer = coordinator.renderer(for: "message", currentText: "")
        let chunks = ["very ", "very ", "good 😄 ", "ỊẠỊ", "\n```\na = a + a\n```"]
        for chunk in chunks { coordinator.appendDelta(chunk, for: "message") }
        coordinator.finishActive()
        XCTAssertEqual(renderer.rawText, chunks.joined())
    }

    func testScheduledFlushDoesNotReplayFinishedMessage() async throws {
        let coordinator = StreamingRendererCoordinator()
        let renderer = coordinator.renderer(for: "message", currentText: "signing ")
        coordinator.appendDelta("also needs a password", for: "message")
        coordinator.finishActive()
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(renderer.rawText, "signing also needs a password")
    }
}
