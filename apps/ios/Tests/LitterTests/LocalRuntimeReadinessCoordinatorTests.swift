import XCTest
@testable import Litter

final class LocalRuntimeReadinessCoordinatorTests: XCTestCase {
    private actor Probe {
        enum Failure: Error { case expected }
        var calls = 0
        var failNext = false

        func failOnce() { failNext = true }
        func prepare() throws {
            calls += 1
            if failNext {
                failNext = false
                throw Failure.expected
            }
        }
    }

    func testRefreshRunsAgainAfterCachedSuccess() async throws {
        let probe = Probe()
        let coordinator = LocalRuntimeReadinessCoordinator { try await probe.prepare() }
        try await coordinator.ensureReady()
        try await coordinator.ensureReady()
        let cachedCalls = await probe.calls
        XCTAssertEqual(cachedCalls, 1)
        try await coordinator.ensureReady(forceRefresh: true)
        let refreshedCalls = await probe.calls
        XCTAssertEqual(refreshedCalls, 2)
    }

    func testFailedRefreshInvalidatesReadinessAndCanRetry() async throws {
        let probe = Probe()
        let coordinator = LocalRuntimeReadinessCoordinator { try await probe.prepare() }
        try await coordinator.ensureReady()
        await probe.failOnce()
        do {
            try await coordinator.ensureReady(forceRefresh: true)
            XCTFail("Refresh should report the preparation failure")
        } catch Probe.Failure.expected {}
        try await coordinator.ensureReady()
        let calls = await probe.calls
        XCTAssertEqual(calls, 3)
    }

    func testConcurrentRequestsSharePreparation() async throws {
        let probe = Probe()
        let coordinator = LocalRuntimeReadinessCoordinator { try await probe.prepare() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try await coordinator.ensureReady() }
            }
            try await group.waitForAll()
        }
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }
}
