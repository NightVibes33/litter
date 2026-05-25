import XCTest
@testable import Litter

final class WatchSizeTests: XCTestCase {
    func testCompactBucket() {
        XCTAssertEqual(WatchSize.from(width: 162), .compact, "40mm SE")
        XCTAssertEqual(WatchSize.from(width: 165), .compact, "compact upper bound")
        XCTAssertEqual(WatchSize.from(width: 100), .compact, "tiny widths still bucket compact")
    }

    func testRegularBucket() {
        XCTAssertEqual(WatchSize.from(width: 166), .regular, "just above compact")
        XCTAssertEqual(WatchSize.from(width: 176), .regular, "41/42mm S7+")
        XCTAssertEqual(WatchSize.from(width: 184), .regular, "44mm SE")
        XCTAssertEqual(WatchSize.from(width: 195), .regular, "regular upper bound")
    }

    func testExpandedBucket() {
        XCTAssertEqual(WatchSize.from(width: 196), .expanded, "just above regular")
        XCTAssertEqual(WatchSize.from(width: 200), .expanded, "46mm S10")
        XCTAssertEqual(WatchSize.from(width: 205), .expanded, "49mm Ultra")
        XCTAssertEqual(WatchSize.from(width: 999), .expanded, "huge widths still bucket expanded")
    }

    func testFontScaleMonotonic() {
        XCTAssertLessThan(WatchSize.compact.fontScale, WatchSize.regular.fontScale)
        XCTAssertLessThan(WatchSize.regular.fontScale, WatchSize.expanded.fontScale)
    }

    func testRegularFontScaleIsIdentity() {
        XCTAssertEqual(WatchSize.regular.fontScale, 1.0)
    }
}
