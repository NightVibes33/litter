import XCTest
@testable import Litter

/// Covers the persistence layer that the watch's
/// `WatchAppStore.forceHydrateFromAppGroup()` reads from. `WatchAppStore`
/// itself lives in the LitterWatch target so it can't be unit-tested
/// directly from the iOS Litter test bundle, but the round-trip behavior
/// here is what the force-hydrate path depends on: a second `save` must
/// be observable to a subsequent `current()` so background refreshes can
/// pick up updates that landed while the watch app was suspended.
final class WatchAppStoreHydrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearAppGroup()
    }

    override func tearDown() {
        clearAppGroup()
        super.tearDown()
    }

    func testWatchSnapshotStoreReturnsTheMostRecentSave() throws {
        let first = makePayload(taskId: "old", title: "old title")
        WatchSnapshotStore.save(first, date: Date(timeIntervalSince1970: 1_000))

        let firstRead = try XCTUnwrap(WatchSnapshotStore.current())
        XCTAssertEqual(firstRead.0.tasks.first?.title, "old title")
        XCTAssertEqual(firstRead.1, Date(timeIntervalSince1970: 1_000))

        let second = makePayload(taskId: "new", title: "new title")
        WatchSnapshotStore.save(second, date: Date(timeIntervalSince1970: 2_000))

        // This is the regression that the watch's `forceHydrateFromAppGroup`
        // relies on: a second `save` must be visible to a subsequent
        // `current()` read so the background refresh task can rehydrate.
        let secondRead = try XCTUnwrap(WatchSnapshotStore.current())
        XCTAssertEqual(secondRead.0.tasks.first?.title, "new title")
        XCTAssertEqual(secondRead.1, Date(timeIntervalSince1970: 2_000))
    }

    func testWatchSnapshotStoreCurrentReturnsNilWhenNoSnapshotSaved() {
        XCTAssertNil(WatchSnapshotStore.current())
    }

    // MARK: - Factories

    private func makePayload(taskId: String, title: String) -> WatchSnapshotPayload {
        let task = WatchTask(
            id: "srv:\(taskId)",
            threadId: taskId,
            serverId: "srv",
            serverName: "srv",
            title: title,
            subtitle: nil,
            status: .idle,
            relativeTime: "",
            steps: [],
            transcript: [],
            pendingApprovalId: nil
        )
        return WatchSnapshotPayload(
            tasks: [task],
            pendingApproval: nil,
            voice: nil,
            theme: nil
        )
    }

    private func clearAppGroup() {
        guard let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroup) else { return }
        defaults.removeObject(forKey: WatchSnapshotStore.payloadKey)
        defaults.removeObject(forKey: WatchSnapshotStore.timestampKey)
    }
}
