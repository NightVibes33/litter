import XCTest
@testable import Litter

final class AppVersionTests: XCTestCase {
    func testDisplayStringUsesMarketingVersion() throws {
        let version = try XCTUnwrap(AppVersion(version: "1.5.2", build: "120"))

        XCTAssertEqual(version.displayString, "1.5.2")
    }

    func testComparisonUsesSemanticVersionBeforeBuildNumber() throws {
        let olderVersionWithHigherBuild = try XCTUnwrap(AppVersion(version: "1.5.1", build: "999"))
        let newerVersionWithLowerBuild = try XCTUnwrap(AppVersion(version: "1.5.2", build: "1"))

        XCTAssertLessThan(olderVersionWithHigherBuild, newerVersionWithLowerBuild)
        XCTAssertFalse(newerVersionWithLowerBuild < olderVersionWithHigherBuild)
    }

    func testComparisonUsesBuildAsTieBreakerForSameVersion() throws {
        let olderBuild = try XCTUnwrap(AppVersion(version: "1.5.2", build: "120"))
        let newerBuild = try XCTUnwrap(AppVersion(version: "1.5.2", build: "121"))

        XCTAssertLessThan(olderBuild, newerBuild)
    }
}
