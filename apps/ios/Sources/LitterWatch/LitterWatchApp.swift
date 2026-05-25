import SwiftUI
import WatchKit
import UserNotifications

/// Identifiers shared with the iPhone notification scheduler. Keep in lock
/// step with `WatchApprovalNotification` on the iOS target — copied here so
/// the watch target doesn't need to link the iOS module.
enum WatchApprovalNotificationConstants {
    static let categoryIdentifier = "litter.approval"
    static let allowActionIdentifier = "litter.approval.allow"
    static let denyActionIdentifier = "litter.approval.deny"
    static let requestIdKey = "requestId"
}

/// Pure routing of a notification response action id to an approval
/// decision. Exposed so unit tests can validate the dispatch table without
/// instantiating UserNotifications types.
enum WatchApprovalActionRouter {
    enum Decision: Equatable {
        case approve(requestId: String)
        case deny(requestId: String)
        case noop
    }

    static func decision(
        forActionIdentifier actionId: String,
        userInfo: [AnyHashable: Any]
    ) -> Decision {
        guard let requestId = userInfo[WatchApprovalNotificationConstants.requestIdKey] as? String,
              !requestId.isEmpty else {
            return .noop
        }
        switch actionId {
        case WatchApprovalNotificationConstants.allowActionIdentifier:
            return .approve(requestId: requestId)
        case WatchApprovalNotificationConstants.denyActionIdentifier:
            return .deny(requestId: requestId)
        default:
            return .noop
        }
    }
}

/// Routes notification action taps from the system into
/// `WatchSessionBridge.shared.sendApprovalDecision`. Owned by
/// `LitterWatchApp` so the singleton survives the whole app lifetime.
final class WatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationDelegate()
    private override init() { super.init() }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let decision = WatchApprovalActionRouter.decision(
            forActionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        switch decision {
        case .approve(let requestId):
            Task { @MainActor in
                WatchSessionBridge.shared.sendApprovalDecision(
                    requestId: requestId,
                    approve: true
                )
                completionHandler()
            }
        case .deny(let requestId):
            Task { @MainActor in
                WatchSessionBridge.shared.sendApprovalDecision(
                    requestId: requestId,
                    approve: false
                )
                completionHandler()
            }
        case .noop:
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

/// Background refresh cadence for the watch's App Group hydrate task. 15
/// minutes is the upper bound watchOS will honor reliably; complications
/// stay fresh during long idle stretches without burning the budget on
/// short turns.
let watchBackgroundRefreshInterval: TimeInterval = 15 * 60

/// `WKApplicationDelegate` that owns the background-refresh lifecycle so
/// the watch can rehydrate its App Group snapshot while suspended. Routes
/// `WKApplicationRefreshBackgroundTask`s to `forceHydrateFromAppGroup`
/// then reschedules the next refresh.
final class LitterWatchAppDelegate: NSObject, WKApplicationDelegate {
    static let shared = LitterWatchAppDelegate()

    func applicationDidFinishLaunching() {
        Self.scheduleNextRefresh()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refresh as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    WatchAppStore.shared.forceHydrateFromAppGroup()
                    Self.scheduleNextRefresh()
                    refresh.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    static func scheduleNextRefresh(now: Date = .now) {
        let preferred = now.addingTimeInterval(watchBackgroundRefreshInterval)
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferred,
            userInfo: nil
        ) { error in
            if let error {
                #if DEBUG
                print("[watch] scheduleBackgroundRefresh failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

/// Root @main for the Litter Watch app. Vertically paginated TabView
/// makes the three hero surfaces reachable via crown/swipe.
@main
struct LitterWatchApp: App {
    @WKApplicationDelegateAdaptor(LitterWatchAppDelegate.self) private var appDelegate
    @StateObject private var store = WatchAppStore.shared
    @StateObject private var theme = WatchThemeStore.shared

    init() {
        WatchSessionBridge.shared.start()
        registerNotificationCategories()
    }

    private func registerNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        center.delegate = WatchNotificationDelegate.shared
        let approval = UNNotificationCategory(
            identifier: WatchApprovalNotificationConstants.categoryIdentifier,
            actions: [
                UNNotificationAction(
                    identifier: WatchApprovalNotificationConstants.allowActionIdentifier,
                    title: "Allow",
                    options: []
                ),
                UNNotificationAction(
                    identifier: WatchApprovalNotificationConstants.denyActionIdentifier,
                    title: "Deny",
                    options: [.destructive]
                ),
            ],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([approval])
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .environmentObject(theme)
                .environment(\.watchSize, WatchSize.current)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.accent)
        }

        WKNotificationScene(
            controller: LitterNotificationController.self,
            category: "litter.task.complete"
        )

        WKNotificationScene(
            controller: LitterNotificationController.self,
            category: WatchApprovalNotificationConstants.categoryIdentifier
        )
    }
}

/// The three-page hero loop: glance → dictate → approve.
///
/// A single root `NavigationStack` wraps the `TabView` so pushed
/// destinations (task detail, transcript, approval) replace the whole
/// pager and the native horizontal edge-swipe-back gesture works.
/// Nesting `NavigationStack` per tab page fought with the vertical
/// page tab view and broke back navigation.
struct WatchRootView: View {
    @EnvironmentObject var store: WatchAppStore
    @ObservedObject private var router = WatchDeepLinkRouter.shared
    @State private var tab: RootTab = .home
    @State private var path: [WatchTask] = []

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $tab) {
                HomeScreen().tag(RootTab.home)
                RealtimeVoiceScreen().tag(RootTab.voice)
                ApprovalScreen().tag(RootTab.approval)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WatchTask.self) { task in
                TaskDetailScreen(task: task)
            }
        }
        .onOpenURL { url in
            router.handle(url)
        }
        .onChange(of: router.pendingDeepLink) { _, destination in
            if let destination { apply(destination) }
        }
        .onAppear {
            if let destination = router.pendingDeepLink {
                apply(destination)
            }
        }
    }

    /// Apply a parsed deep-link destination. Routed via
    /// `WatchDeepLinkRouter` so both `.onOpenURL` and AppIntent-triggered
    /// launches use the same single source of truth.
    private func apply(_ destination: WatchDeepLinkRouter.Destination) {
        switch destination {
        case .task(let id):
            guard let task = store.tasks.first(where: { $0.id == id }) else {
                path.removeAll()
                tab = .home
                router.clear()
                return
            }
            tab = .home
            path = [task]
        case .server(let id):
            // Drill into the most-recent task on that server when we have
            // one; otherwise just land on home (the user will see the
            // server's rows in the snapshot).
            if let task = store.tasks.first(where: { $0.serverId == id }) {
                tab = .home
                path = [task]
                store.focus(on: task)
            } else {
                path.removeAll()
                tab = .home
            }
        case .voice:
            path.removeAll()
            tab = .voice
        }
        router.clear()
    }
}

enum RootTab: Hashable {
    case home, voice, approval
}

final class LitterNotificationController: WKUserNotificationHostingController<NotificationScreen> {
    private var currentNotification: UNNotification?

    override var body: NotificationScreen {
        NotificationScreen(notification: currentNotification)
    }

    override func didReceive(_ notification: UNNotification) {
        currentNotification = notification
    }
}
