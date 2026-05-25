import AppIntents

/// AppShortcuts surface for the watch app. These show up in the Shortcuts
/// app and (on Apple Watch Ultra) are assignable to the Action Button via
/// Settings → Action Button → Shortcut.
struct LitterWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendPromptIntent(),
            phrases: [
                "Send a task to \(.applicationName)"
            ],
            shortTitle: "Send Task",
            systemImageName: "mic.circle.fill"
        )
        AppShortcut(
            intent: OpenServerOnWatchIntent(),
            phrases: [
                "Open a server in \(.applicationName)",
                "Open \(\.$server) in \(.applicationName)"
            ],
            shortTitle: "Open Server",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: StartVoiceOnWatchIntent(),
            phrases: [
                "Start voice in \(.applicationName)"
            ],
            shortTitle: "Start Voice",
            systemImageName: "waveform.circle.fill"
        )
    }
}
