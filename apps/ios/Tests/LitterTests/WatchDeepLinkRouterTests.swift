import XCTest
@testable import Litter

final class WatchDeepLinkRouterTests: XCTestCase {

    // MARK: - URL parsing

    func testParsesTaskUrl() {
        let url = URL(string: "litter-watch://task/macbook:t1")!
        XCTAssertEqual(WatchDeepLinkRouter.destination(for: url), .task(id: "macbook:t1"))
    }

    func testParsesServerUrl() {
        let url = URL(string: "litter-watch://server/macbook-pro")!
        XCTAssertEqual(WatchDeepLinkRouter.destination(for: url), .server(id: "macbook-pro"))
    }

    func testParsesVoiceUrl() {
        let url = URL(string: "litter-watch://voice")!
        XCTAssertEqual(WatchDeepLinkRouter.destination(for: url), .voice)
    }

    func testParsesVoiceUrlWithTrailingPath() {
        // Some shortcut runners append a trailing slash; treat as voice.
        let url = URL(string: "litter-watch://voice/")!
        XCTAssertEqual(WatchDeepLinkRouter.destination(for: url), .voice)
    }

    func testRejectsForeignScheme() {
        let url = URL(string: "litter://task/x")!
        XCTAssertNil(WatchDeepLinkRouter.destination(for: url))
    }

    func testRejectsUnknownHost() {
        let url = URL(string: "litter-watch://settings")!
        XCTAssertNil(WatchDeepLinkRouter.destination(for: url))
    }

    func testRejectsTaskWithoutIdentifier() {
        let url = URL(string: "litter-watch://task/")!
        XCTAssertNil(WatchDeepLinkRouter.destination(for: url))
    }

    func testRejectsServerWithoutIdentifier() {
        let url = URL(string: "litter-watch://server/")!
        XCTAssertNil(WatchDeepLinkRouter.destination(for: url))
    }
}
