import XCTest
@testable import Litter

final class WatchThemePayloadTests: XCTestCase {
    func testRoundTripPreservesEveryToken() throws {
        let theme = WatchThemePayload(
            appearanceMode: .dark,
            isDark: true,
            accent: "#F59E0B",
            accentStrong: "#D97706",
            textPrimary: "#FCFCFC",
            textSecondary: "#8F8F8F",
            textMuted: "#555555",
            surface: "#0E0E0E",
            surfaceLight: "#1A1A1A",
            border: "#222222",
            danger: "#FF5555",
            success: "#00FF9C",
            warning: "#E2A644",
            textOnAccent: "#1F2937",
            backgroundTop: "#000000",
            backgroundBottom: "#0A0A0A"
        )
        let payload = WatchSnapshotPayload(
            tasks: [], pendingApproval: nil, voice: nil, theme: theme
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchSnapshotPayload.self, from: data)

        XCTAssertEqual(decoded.theme, theme)
        XCTAssertEqual(decoded.theme?.appearanceMode, .dark)
        XCTAssertEqual(decoded.theme?.accent, "#F59E0B")
    }

    /// A payload encoded by an older iPhone build (no `theme` key) must
    /// still decode cleanly. Watch then falls back to its WatchTheme
    /// defaults via `WatchThemeStore`.
    func testSnapshotWithoutThemeKeyDecodesAsNil() throws {
        let json = #"{"tasks":[],"pendingApproval":null,"voice":null}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WatchSnapshotPayload.self, from: json)
        XCTAssertNil(decoded.theme)
        XCTAssertTrue(decoded.tasks.isEmpty)
    }

    /// A payload encoded by an older iPhone build that doesn't know about
    /// hiddenTasks must still decode cleanly so the new watch app can run
    /// against an old phone build (and vice versa for persisted snapshots).
    func testSnapshotWithoutHiddenTasksKeyDecodesAsNil() throws {
        let json = #"{"tasks":[],"pendingApproval":null,"voice":null}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WatchSnapshotPayload.self, from: json)
        XCTAssertNil(decoded.hiddenTasks)
    }

    func testSnapshotRoundTripsHiddenTasks() throws {
        let task = WatchTask(
            id: "macbook:hidden",
            threadId: "hidden",
            serverId: "macbook",
            serverName: "macbook",
            title: "tucked away",
            subtitle: nil,
            status: .idle,
            relativeTime: "2h",
            steps: [],
            transcript: [],
            pendingApprovalId: nil
        )
        let payload = WatchSnapshotPayload(
            tasks: [], pendingApproval: nil, voice: nil, theme: nil,
            hiddenTasks: [task]
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchSnapshotPayload.self, from: data)

        XCTAssertEqual(decoded.hiddenTasks?.count, 1)
        XCTAssertEqual(decoded.hiddenTasks?.first?.threadId, "hidden")
    }
}
