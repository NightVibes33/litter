import XCTest
@testable import Litter

final class WatchHapticDetectorTests: XCTestCase {

    // MARK: - First-hydration suppression

    func testFirstHydrationEmitsNoHapticsEvenWhenStatusesAreInteresting() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [],
            newTasks: [
                makeTask(id: "1", status: .running),
                makeTask(id: "2", status: .needsApproval),
            ],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100),
            isFirstHydration: true
        )
        XCTAssertEqual(outcome.haptics, [])
        XCTAssertEqual(outcome.updatedLastFired, [:])
    }

    // MARK: - Status transitions

    func testIdleToRunningFiresStart() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .idle)],
            newTasks: [makeTask(id: "1", status: .running)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [.start])
    }

    func testRunningToIdleFiresSuccess() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .running)],
            newTasks: [makeTask(id: "1", status: .idle)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [.success])
    }

    func testRunningToErrorFiresFailure() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .running)],
            newTasks: [makeTask(id: "1", status: .error)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [.failure])
    }

    func testIdleToNeedsApprovalFiresNotification() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .idle)],
            newTasks: [makeTask(id: "1", status: .needsApproval)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [.notification])
    }

    func testRunningToNeedsApprovalFiresNotification() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .running)],
            newTasks: [makeTask(id: "1", status: .needsApproval)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [.notification])
    }

    func testStatusUnchangedFiresNothing() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .running)],
            newTasks: [makeTask(id: "1", status: .running)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [])
    }

    func testBrandNewRunningTaskFiresNothing() {
        // A new task showing up as `running` typically means the user just
        // kicked one off on the phone — no haptic needed.
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [],
            newTasks: [makeTask(id: "new", status: .running)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [])
    }

    func testBrandNewNeedsApprovalTaskFiresNotification() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [],
            newTasks: [makeTask(id: "new", status: .needsApproval)],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [.notification])
    }

    // MARK: - Throttle + dedupe

    func testSameHapticThrottledWithin2sIsSuppressed() {
        let detector = WatchHapticDetector(throttle: 2)
        let firstFireAt = Date(timeIntervalSince1970: 100)
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .running)],
            newTasks: [makeTask(id: "1", status: .idle)],
            lastFired: [.success: firstFireAt],
            now: firstFireAt.addingTimeInterval(1.5)
        )
        XCTAssertEqual(outcome.haptics, [])
        // Last fired should be unchanged because we did not emit.
        XCTAssertEqual(outcome.updatedLastFired[.success], firstFireAt)
    }

    func testSameHapticAfterThrottleFires() {
        let detector = WatchHapticDetector(throttle: 2)
        let firstFireAt = Date(timeIntervalSince1970: 100)
        let now = firstFireAt.addingTimeInterval(2.5)
        let outcome = detector.evaluate(
            oldTasks: [makeTask(id: "1", status: .running)],
            newTasks: [makeTask(id: "1", status: .idle)],
            lastFired: [.success: firstFireAt],
            now: now
        )
        XCTAssertEqual(outcome.haptics, [.success])
        XCTAssertEqual(outcome.updatedLastFired[.success], now)
    }

    func testMultipleTasksFlippingToSameStatusOnlyFireOneHaptic() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [
                makeTask(id: "a", status: .idle),
                makeTask(id: "b", status: .idle),
            ],
            newTasks: [
                makeTask(id: "a", status: .running),
                makeTask(id: "b", status: .running),
            ],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(outcome.haptics, [.start])
    }

    func testTransitionsToDifferentHapticsCoexistInOneDiff() {
        let detector = WatchHapticDetector()
        let outcome = detector.evaluate(
            oldTasks: [
                makeTask(id: "a", status: .idle),
                makeTask(id: "b", status: .running),
            ],
            newTasks: [
                makeTask(id: "a", status: .running),    // → start
                makeTask(id: "b", status: .idle),       // → success
            ],
            lastFired: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(Set(outcome.haptics), Set([.start, .success]))
    }

    // MARK: - Factory

    private func makeTask(id: String, status: WatchTask.Status) -> WatchTask {
        WatchTask(
            id: id,
            threadId: id,
            serverId: "srv",
            serverName: "srv",
            title: "task \(id)",
            subtitle: nil,
            status: status,
            relativeTime: "",
            steps: [],
            transcript: [],
            pendingApprovalId: status == .needsApproval ? "ap-\(id)" : nil
        )
    }
}
