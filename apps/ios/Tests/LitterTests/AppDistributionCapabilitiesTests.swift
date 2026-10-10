import XCTest
@testable import Litter

@MainActor
final class AppDistributionCapabilitiesTests: XCTestCase {
    func testAppStoreBuildNeverEnablesSideloadBackgroundMonitor() {
        if AppDistributionCapabilities.isAppStoreSafe {
            XCTAssertFalse(AppDistributionCapabilities.includesKittyStore)
            XCTAssertFalse(AppDistributionCapabilities.includesEmexDE)
            XCTAssertFalse(AppDistributionCapabilities.shouldRunSideloadBuildKitMonitor)
            XCTAssertFalse(AppDistributionCapabilities.unlocksProForSideload)
        }
    }

    func testSideloadMonitorRequiresBundledNyxian() {
        XCTAssertEqual(
            AppDistributionCapabilities.shouldRunSideloadBuildKitMonitor,
            !AppDistributionCapabilities.isAppStoreSafe && AppDistributionCapabilities.includesEmexDE
        )
    }
}
