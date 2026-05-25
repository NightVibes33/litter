import Foundation

/// View-model types for the watch experience. Hydrated from the shared Rust
/// `MobileClient` store via WatchConnectivity — see `WatchCompanionBridge`
/// (iOS side) and `WatchSessionBridge` (watch side).
struct WatchTaskStep: Identifiable, Hashable, Codable {
    enum State: String, Hashable, Codable {
        case done, active, pending
    }

    var id = UUID()
    let tool: String
    let arg: String
    let state: State
}

struct WatchApproval: Hashable, Codable, Identifiable {
    /// JSON-RPC request id — echoed back when the user taps allow/deny.
    let id: String
    let command: String
    let target: String
    let diffSummary: String

    enum Kind: String, Codable {
        case command, fileChange, permissions, mcpElicitation
    }
    let kind: Kind
}

struct WatchTranscriptTurn: Identifiable, Hashable, Codable {
    enum Role: String, Hashable, Codable {
        case user, assistant, system
    }
    var id = UUID()
    let role: Role
    let text: String
    let faded: Bool
}

/// One file's worth of unified-diff content surfaced on the watch's diffs
/// screen. The phone trims `diff` to a hard byte budget before shipping so
/// the WatchConnectivity application-context payload stays well under the
/// 256 KB limit even when a task touches many files.
struct WatchFileDiff: Identifiable, Hashable, Codable {
    /// `path` is unique within a task — collapsed to "most recent diff per
    /// file" in the projection, so it doubles as a stable id.
    var id: String { path }
    let path: String
    /// Upstream kind label ("add", "modify", "delete", …); the UI uses this
    /// to pick an icon, not for parsing.
    let kind: String
    let additions: Int
    let deletions: Int
    /// Unified-diff text, possibly tail-truncated with a `…` sentinel line.
    let diff: String
    /// True when the phone trimmed the diff to stay under the size budget.
    /// The watch surfaces this as a small "truncated" hint.
    let truncated: Bool
}

/// A single conversation/thread row — the watch's equivalent of the iPhone
/// sessions list. Every Codex thread the phone knows about becomes a task
/// row. The list is sorted by recent activity.
struct WatchTask: Identifiable, Hashable, Codable {
    enum Status: String, Hashable, Codable {
        case running        // has an active turn
        case needsApproval  // has pending approval
        case idle           // completed, at rest
        case error
    }

    /// "{serverId}:{threadId}" — stable across snapshots.
    let id: String
    let threadId: String
    let serverId: String
    let serverName: String
    /// Thread title; falls back to the first user message if untitled.
    let title: String
    /// Short preview line — usually the most recent assistant turn or
    /// tool call; may be empty.
    let subtitle: String?
    let status: Status
    /// Relative time label — "2m", "1h", "yesterday", etc. Empty when
    /// there is no last-activity timestamp.
    let relativeTime: String
    /// Recent tool call steps (for the detail view). Empty for idle
    /// threads.
    let steps: [WatchTaskStep]
    /// The last few transcript turns of this thread, shipped inline so the
    /// detail/transcript view doesn't need a round-trip to populate.
    let transcript: [WatchTranscriptTurn]
    /// If this task has a pending approval, its request id.
    let pendingApprovalId: String?

    // MARK: - iPhone-parity row enrichment (all optional for back-compat)
    var model: String?
    var cwd: String?
    var turnCount: Int?
    var toolCallCount: Int?
    var diffAdditions: Int?
    var diffDeletions: Int?
    var contextPercent: Int?
    var hasTurnActive: Bool?
    /// Most recent tool the AI is/was running. Set only when the subtitle
    /// is the assistant's reply (so this stays a small secondary chip
    /// instead of duplicating the subtitle text).
    var lastTool: String?
    /// Per-file diffs surfaced by the watch's full diffs screen, ordered
    /// most-recent first and capped by the projection. `nil`/empty when
    /// the task has no file changes yet (or older iPhone builds that
    /// don't ship diffs).
    var diffs: [WatchFileDiff]?
}

/// Slice of realtime voice session state pushed to the watch so it can
/// render the transcript, audio level, and mute state without re-deriving
/// from upstream events.
struct WatchVoiceState: Codable, Hashable {
    enum Mode: String, Codable, Hashable {
        case idle, listening, speaking, thinking, error
    }

    let mode: Mode
    let serverId: String?
    let threadId: String?
    let recentTurns: [WatchTranscriptTurn]
    /// Most recent input level scaled to [0, 1].
    let audioLevel: Double
    let isMuted: Bool
}

/// Resolved theme palette the iPhone pushes to the watch so every screen can
/// reflect the user's selected light/dark theme. Hex strings, "#RRGGBB".
struct WatchThemePayload: Codable, Hashable {
    enum AppearanceMode: String, Codable, Hashable {
        case system, light, dark
    }

    let appearanceMode: AppearanceMode
    /// Phone-resolved colorScheme at push time — already honors `.system`.
    let isDark: Bool

    let accent: String
    let accentStrong: String
    let textPrimary: String
    let textSecondary: String
    let textMuted: String
    let surface: String
    let surfaceLight: String
    let border: String
    let danger: String
    let success: String
    let warning: String
    let textOnAccent: String
    let backgroundTop: String
    let backgroundBottom: String
}

/// Wire-format the iOS app pushes to the watch via `updateApplicationContext`.
struct WatchSnapshotPayload: Codable, Hashable {
    var tasks: [WatchTask]
    var pendingApproval: WatchApproval?
    var voice: WatchVoiceState?
    /// Resolved palette + appearance for the watch UI. Optional so older
    /// iPhone builds (and old persisted snapshots) decode cleanly.
    var theme: WatchThemePayload?
    /// Tasks the user has hidden from home. Optional so older iPhone builds
    /// (and old persisted snapshots) decode cleanly — watch shows no
    /// hidden screen until it sees a non-nil/non-empty list.
    var hiddenTasks: [WatchTask]?
}

#if DEBUG
/// Minimal fixtures for SwiftUI `#Preview { ... }` blocks only — never
/// referenced from production code paths.
enum WatchPreviewFixtures {
    static let tasks: [WatchTask] = [
        WatchTask(
            id: "macbook-pro:t1",
            threadId: "t1",
            serverId: "macbook-pro",
            serverName: "macbook-pro",
            title: "fix auth token expiry",
            subtitle: "edit_file src/auth.go",
            status: .running,
            relativeTime: "now",
            steps: [
                WatchTaskStep(tool: "read_file", arg: "src/auth.go", state: .done),
                WatchTaskStep(tool: "edit_file", arg: "src/auth.go", state: .active),
                WatchTaskStep(tool: "run_tests", arg: "./...",       state: .pending),
            ],
            transcript: [
                WatchTranscriptTurn(role: .user,      text: "fix auth expiry", faded: false),
                WatchTranscriptTurn(role: .assistant, text: "editing...",      faded: false),
            ],
            pendingApprovalId: nil,
            model: "gpt-5-codex",
            cwd: "/Users/dev/litter",
            turnCount: 4,
            toolCallCount: 11,
            diffAdditions: 32,
            diffDeletions: 7,
            contextPercent: 18,
            hasTurnActive: true,
            lastTool: nil,
            diffs: [
                WatchFileDiff(
                    path: "src/auth.go",
                    kind: "modify",
                    additions: 4,
                    deletions: 2,
                    diff: """
                    @@ -10,7 +10,9 @@
                     func refresh(t *Token) error {
                    -    if t.expired() {
                    -        return errors.New(\"expired\")
                    +    if t.expiredAt.Before(time.Now()) {
                    +        return t.rotate()
                    +    }
                         return nil
                     }
                    """,
                    truncated: false
                ),
                WatchFileDiff(
                    path: "src/auth_test.go",
                    kind: "add",
                    additions: 28,
                    deletions: 5,
                    diff: """
                    @@ -0,0 +1,8 @@
                    +func TestRefreshRotatesExpired(t *testing.T) {
                    +    tok := &Token{expiredAt: time.Now().Add(-time.Minute)}
                    +    if err := refresh(tok); err != nil {
                    +        t.Fatal(err)
                    +    }
                    +}
                    """,
                    truncated: false
                ),
            ]
        ),
        WatchTask(
            id: "macbook-pro:t2",
            threadId: "t2",
            serverId: "macbook-pro",
            serverName: "macbook-pro",
            title: "refactor session store",
            subtitle: "pushed to feature/session-split",
            status: .idle,
            relativeTime: "12m",
            steps: [],
            transcript: [],
            pendingApprovalId: nil
        ),
        WatchTask(
            id: "studio.lan:t3",
            threadId: "t3",
            serverId: "studio.lan",
            serverName: "studio.lan",
            title: "deploy staging",
            subtitle: "awaiting approval: git push",
            status: .needsApproval,
            relativeTime: "2m",
            steps: [],
            transcript: [],
            pendingApprovalId: "approval-id"
        ),
    ]

    static let hiddenTasks: [WatchTask] = [
        WatchTask(
            id: "macbook-pro:hidden1",
            threadId: "hidden1",
            serverId: "macbook-pro",
            serverName: "macbook-pro",
            title: "old session — bumped css",
            subtitle: nil,
            status: .idle,
            relativeTime: "yesterday",
            steps: [],
            transcript: [],
            pendingApprovalId: nil
        ),
    ]

    static let approval = WatchApproval(
        id: "preview",
        command: "git push",
        target: "origin/fix-auth-expiry",
        diffSummary: "+12 -3 · 1 file",
        kind: .command
    )

    static let voice = WatchVoiceState(
        mode: .listening,
        serverId: "local",
        threadId: "voice-thread",
        recentTurns: [
            WatchTranscriptTurn(role: .user,      text: "what's on my plate", faded: false),
            WatchTranscriptTurn(role: .assistant, text: "two open threads…",  faded: false),
        ],
        audioLevel: 0.42,
        isMuted: false
    )

    static let transcript: [WatchTranscriptTurn] = [
        WatchTranscriptTurn(role: .user,      text: "fix the auth test",   faded: false),
        WatchTranscriptTurn(role: .assistant, text: "done. tests pass.",   faded: false),
    ]

    /// Dark ginger fallback so previews look like today's hardcoded theme.
    static let theme = WatchThemePayload(
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
}
#endif
