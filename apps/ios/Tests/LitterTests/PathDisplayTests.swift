import XCTest
@testable import Litter

final class PathDisplayTests: XCTestCase {
    func testRemoteWindowsUserHomeAbbreviatesToTilde() {
        XCTAssertEqual(PathDisplay.display("C:\\Users\\npace", isLocal: false), "~")
    }

    func testRemoteWindowsUserPathAbbreviatesWithBackslashes() {
        XCTAssertEqual(PathDisplay.display("C:\\Users\\npace\\dev\\litter", isLocal: false), "~\\dev\\litter")
    }

    func testRemotePosixHomePathStillAbbreviates() {
        XCTAssertEqual(PathDisplay.display("/Users/npace/dev/litter", isLocal: false), "~/dev/litter")
    }

    func testRemoteWindowsDisplayPathExpandsUsingResolvedHome() {
        XCTAssertEqual(
            PathDisplay.expand("~\\dev\\litter", isLocal: false, remoteHome: "C:\\Users\\npace"),
            "C:\\Users\\npace\\dev\\litter"
        )
    }

    func testRemoteWindowsDisplayPathAcceptsForwardSlashSuffix() {
        XCTAssertEqual(
            PathDisplay.expand("~/dev/litter", isLocal: false, remoteHome: "C:\\Users\\npace"),
            "C:\\Users\\npace\\dev\\litter"
        )
    }

    func testRemotePosixDisplayPathExpandsUsingResolvedHome() {
        XCTAssertEqual(
            PathDisplay.expand("~/dev/litter", isLocal: false, remoteHome: "/home/npace"),
            "/home/npace/dev/litter"
        )
    }
}
