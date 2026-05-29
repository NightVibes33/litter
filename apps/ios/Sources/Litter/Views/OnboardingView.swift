import Combine
import Foundation
import SwiftUI

struct LitterOnboardingState {
    static let currentVersion = 1
    static let completedVersionKey = "litterOnboardingCompletedVersion"
    static let replayRequestedKey = "litterOnboardingReplayRequested"
    static let fileWorkspaceInitialDirectoryKey = "litterFileWorkspaceInitialDirectory"
}

enum LitterOnboardingPresentationMode {
    case firstRun
    case replay
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppState.self) private var appState

    let mode: LitterOnboardingPresentationMode
    let onFinish: () -> Void
    let onOpenFiles: (String) -> Void
    let onOpenTerminal: (String) -> Void
    let onOpenServerPicker: () -> Void
    let onOpenSettingsRoute: (String) -> Void

    @StateObject private var readiness = LitterOnboardingReadinessStore()
    @State private var page: LitterOnboardingPage = .welcome
    @State private var demoState: DemoWorkspaceState = .idle

    var body: some View {
        NavigationStack {
            ZStack {
                LitterTheme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    TabView(selection: $page) {
                        ForEach(LitterOnboardingPage.allCases) { page in
                            pageContent(page)
                                .tag(page)
                                .padding(.horizontal, 20)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    footer
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if mode == .replay {
                        Button("Close") { onFinish() }
                            .foregroundStyle(LitterTheme.accent)
                    } else {
                        Button("Skip") { onFinish() }
                            .foregroundStyle(LitterTheme.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await readiness.refresh(appModel: appModel, appState: appState) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(LitterTheme.accent)
                    .disabled(readiness.isRefreshing)
                    .accessibilityLabel("Refresh onboarding checks")
                }
            }
        }
        .interactiveDismissDisabled(mode == .firstRun)
        .task { await readiness.refresh(appModel: appModel, appState: appState) }
    }

    private var header: some View {
        VStack(spacing: 14) {
            BrandLogo(size: 58)
            VStack(spacing: 4) {
                Text(page.title)
                    .litterFont(.title2, weight: .bold)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(page.subtitle)
                    .litterFont(.subheadline)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            pageDots
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(LitterOnboardingPage.allCases) { item in
                Capsule()
                    .fill(item == page ? LitterTheme.accent : LitterTheme.border.opacity(0.75))
                    .frame(width: item == page ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: page)
            }
        }
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                moveBack()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .tint(LitterTheme.textSecondary)
            .disabled(page == LitterOnboardingPage.allCases.first)

            Button {
                if page == LitterOnboardingPage.allCases.last {
                    onFinish()
                } else {
                    moveNext()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(page == LitterOnboardingPage.allCases.last ? "Get Started" : "Continue")
                        .litterFont(.subheadline, weight: .semibold)
                    Image(systemName: page == LitterOnboardingPage.allCases.last ? "checkmark" : "chevron.right")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(LitterTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func pageContent(_ page: LitterOnboardingPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch page {
                case .welcome:
                    welcomePage
                case .runtime:
                    runtimePage
                case .workspace:
                    workspacePage
                case .buildKit:
                    buildKitPage
                case .personalize:
                    personalizePage
                case .checklist:
                    checklistPage
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroPanel(
                systemImage: "iphone.gen3.radiowaves.left.and.right",
                title: "Your iPhone coding workspace",
                detail: "Litter brings AI chat, local files, a shared terminal, remote machines, and iOS build tools into one mobile workspace."
            )
            featureGrid([
                .init(icon: "bubble.left.and.text.bubble.right", title: "AI threads", detail: "Start, resume, fork, and inspect coding sessions."),
                .init(icon: "folder", title: "Fakefs files", detail: "Browse the same /root runtime the bot uses."),
                .init(icon: "terminal", title: "Shared terminal", detail: "Run commands directly in the embedded iSH shell."),
                .init(icon: "hammer", title: "Swift BuildKit", detail: "Check Swift and build iOS artifacts when assets are installed.")
            ])
        }
    }

    private var runtimePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            checkCard(readiness.check(.runtime))
            routeCard(
                icon: ChatRuntimeMode.chatGPTAccount.systemImage,
                title: "ChatGPT Account",
                detail: "Use the signed-in route for normal Litter conversations and hosted models.",
                actionTitle: "Open AI Providers",
                action: { finishAndOpen { onOpenSettingsRoute("aiProviders") } }
            )
            routeCard(
                icon: ChatRuntimeMode.computerBridge.systemImage,
                title: "Computer Bridge",
                detail: "Connect to a desktop Codex app-server or SSH host when you want full machine resources.",
                actionTitle: "Add Server",
                action: { finishAndOpen(onOpenServerPicker) }
            )
        }
    }

    private var workspacePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            checkCard(readiness.check(.shell))
            checkCard(readiness.check(.workspace))
            actionPanel(
                icon: "folder.fill",
                title: "Files start at /root",
                detail: "The browser can show hidden files, shortcuts, builds, commands, and files the bot mentions.",
                primaryTitle: "Open Files",
                primaryAction: { finishAndOpen { onOpenFiles(HomeAnchor.path) } },
                secondaryTitle: "Open Terminal",
                secondaryAction: { finishAndOpen { onOpenTerminal(HomeAnchor.path) } }
            )
            demoWorkspacePanel
        }
    }

    private var buildKitPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            checkCard(readiness.check(.buildKit))
            heroPanel(
                systemImage: "hammer.fill",
                title: "iOS-only build tools",
                detail: "BuildKit focuses on commands that matter on iPhone: swift, swiftc, litter-swift-check, self-test, build status, and unsigned IPA packaging."
            )
            commandStrip(["swift --version", "litter-swift-check hello.swift", "litter-swift-selftest", "litter-build-status"])
            actionPanel(
                icon: "shippingbox.fill",
                title: "Private assets unlock native builds",
                detail: "Full Swift/iOS compilation needs the private BuildKit asset bundle with CoreCompiler, support libraries, native driver, and iPhoneOS SDK.",
                primaryTitle: "Open BuildKit",
                primaryAction: { finishAndOpen { onOpenSettingsRoute("buildKit") } },
                secondaryTitle: "Terminal",
                secondaryAction: { finishAndOpen { onOpenTerminal(HomeAnchor.path) } }
            )
        }
    }

    private var personalizePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureGrid([
                .init(icon: "paintbrush", title: "Themes", detail: "Pick light and dark app themes."),
                .init(icon: "photo", title: "Wallpapers", detail: "Use generated, image, video, or solid backgrounds."),
                .init(icon: "text.cursor", title: "Typing effects", detail: "Tune streaming text effects, speed, and reveal style."),
                .init(icon: "pip", title: "PiP", detail: "Keep a live turn visible while using other apps.")
            ])
            actionPanel(
                icon: "slider.horizontal.3",
                title: "Make the workspace yours",
                detail: "Start with Appearance, then tune each thread from conversation info when you want per-thread style.",
                primaryTitle: "Open Appearance",
                primaryAction: { finishAndOpen { onOpenSettingsRoute("appearance") } },
                secondaryTitle: "Conversation Settings",
                secondaryAction: { finishAndOpen { onOpenSettingsRoute("conversation") } }
            )
        }
    }

    private var checklistPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Setup checklist")
                    .litterFont(.headline, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                ForEach(readiness.checks) { check in
                    checkRow(check)
                }
            }
            .padding(14)
            .background(LitterTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(LitterTheme.border.opacity(0.6), lineWidth: 1))

            actionPanel(
                icon: "sparkles",
                title: "Ready for your first turn",
                detail: "Open a project folder, pick the runtime you want, and ask Litter to inspect or change real files.",
                primaryTitle: "Start a Thread",
                primaryAction: { onFinish() },
                secondaryTitle: "Open Files",
                secondaryAction: { finishAndOpen { onOpenFiles(HomeAnchor.path) } }
            )
        }
    }

    private var demoWorkspacePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: demoState.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(demoState.tint)
                    .frame(width: 34, height: 34)
                    .background(demoState.tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional demo workspace")
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text(demoState.message)
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    Task { await createDemoWorkspace() }
                } label: {
                    if demoState == .creating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(demoState == .created ? "Created" : "Create Demo", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(LitterTheme.accent)
                .disabled(demoState == .creating || demoState == .created)

                Button("Open") {
                    finishAndOpen { onOpenFiles(LitterOnboardingDemoWorkspace.path) }
                }
                .buttonStyle(.bordered)
                .tint(LitterTheme.accent)
                .disabled(demoState != .created)
            }
        }
        .padding(14)
        .background(LitterTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(LitterTheme.border.opacity(0.6), lineWidth: 1))
    }

    private func heroPanel(systemImage: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(LitterTheme.accent)
            Text(title)
                .litterFont(.title3, weight: .bold)
                .foregroundStyle(LitterTheme.textPrimary)
            Text(detail)
                .litterFont(.subheadline)
                .foregroundStyle(LitterTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LitterTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LitterTheme.border.opacity(0.6), lineWidth: 1))
    }

    private func featureGrid(_ features: [OnboardingFeature]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 12)], spacing: 12) {
            ForEach(features) { feature in
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: feature.icon)
                        .font(.headline)
                        .foregroundStyle(LitterTheme.accent)
                    Text(feature.title)
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text(feature.detail)
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .padding(12)
                .background(LitterTheme.surface.opacity(0.64), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(LitterTheme.border.opacity(0.55), lineWidth: 1))
            }
        }
    }

    private func routeCard(icon: String, title: String, detail: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        actionPanel(icon: icon, title: title, detail: detail, primaryTitle: actionTitle, primaryAction: action, secondaryTitle: nil, secondaryAction: nil)
    }

    private func actionPanel(
        icon: String,
        title: String,
        detail: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LitterTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(LitterTheme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text(detail)
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(LitterTheme.accent)
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .tint(LitterTheme.accent)
                }
            }
        }
        .padding(14)
        .background(LitterTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(LitterTheme.border.opacity(0.6), lineWidth: 1))
    }

    private func checkCard(_ check: LitterOnboardingCheck) -> some View {
        checkRow(check)
            .padding(14)
            .background(LitterTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(LitterTheme.border.opacity(0.6), lineWidth: 1))
    }

    private func checkRow(_ check: LitterOnboardingCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.status.iconName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(check.status.tint)
                .frame(width: 26, height: 26)
                .background(check.status.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(check.title)
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                Text(check.detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func commandStrip(_ commands: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(commands, id: \.self) { command in
                Text("$ \(command)")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(LitterTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(LitterTheme.codeBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func createDemoWorkspace() async {
        guard demoState != .creating else { return }
        demoState = .creating
        do {
            _ = try await LitterOnboardingDemoWorkspace.createIfNeeded()
            demoState = .created
            await readiness.refresh(appModel: appModel, appState: appState)
        } catch {
            demoState = .failed(error.localizedDescription)
        }
    }

    private func finishAndOpen(_ action: @escaping () -> Void) {
        onFinish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            action()
        }
    }

    private func moveBack() {
        guard let previous = page.previous else { return }
        withAnimation(.easeInOut(duration: 0.2)) { page = previous }
    }

    private func moveNext() {
        guard let next = page.next else { return }
        withAnimation(.easeInOut(duration: 0.2)) { page = next }
    }
}

private enum LitterOnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case runtime
    case workspace
    case buildKit
    case personalize
    case checklist

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Build with Litter"
        case .runtime: return "Pick your runtime"
        case .workspace: return "Files and terminal"
        case .buildKit: return "Swift on iPhone"
        case .personalize: return "Make it yours"
        case .checklist: return "You are ready"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "A practical tour of the workspace you will use every day."
        case .runtime: return "Use hosted AI or connect a computer for local/private models."
        case .workspace: return "The bot, file browser, and terminal share the same iSH fakefs."
        case .buildKit: return "Understand what works on device and what needs private assets."
        case .personalize: return "Tune the interface without losing the developer workflow."
        case .checklist: return "Live checks show what is ready and what needs setup."
        }
    }

    var previous: LitterOnboardingPage? {
        LitterOnboardingPage(rawValue: rawValue - 1)
    }

    var next: LitterOnboardingPage? {
        LitterOnboardingPage(rawValue: rawValue + 1)
    }
}

private struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

private enum DemoWorkspaceState: Equatable {
    case idle
    case creating
    case created
    case failed(String)

    var iconName: String {
        switch self {
        case .idle: return "folder.badge.plus"
        case .creating: return "hourglass"
        case .created: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle, .creating: return LitterTheme.accent
        case .created: return LitterTheme.success
        case .failed: return LitterTheme.warning
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Create /root/litter/welcome with a README, hello.swift, and LitterBuild.json. Nothing is created unless you tap the button."
        case .creating:
            return "Creating files in the iSH fakefs without overwriting anything already there."
        case .created:
            return "Demo workspace is ready at /root/litter/welcome."
        case .failed(let message):
            return message
        }
    }
}

private enum LitterOnboardingCheckKind: String, CaseIterable, Identifiable {
    case shell
    case workspace
    case paths
    case runtime
    case buildKit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shell: return "Local shell bridge"
        case .workspace: return "File browser access"
        case .paths: return "Expected fakefs paths"
        case .runtime: return "Conversation route"
        case .buildKit: return "Swift BuildKit"
        }
    }
}

private enum LitterOnboardingCheckStatus: Equatable {
    case checking
    case ready
    case warning

    var iconName: String {
        switch self {
        case .checking: return "hourglass"
        case .ready: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .checking: return LitterTheme.textMuted
        case .ready: return LitterTheme.success
        case .warning: return LitterTheme.warning
        }
    }
}

private struct LitterOnboardingCheck: Identifiable, Equatable {
    let kind: LitterOnboardingCheckKind
    var status: LitterOnboardingCheckStatus
    var detail: String

    var id: String { kind.rawValue }
    var title: String { kind.title }
}

@MainActor
private final class LitterOnboardingReadinessStore: ObservableObject {
    @Published private(set) var checks: [LitterOnboardingCheck]
    @Published private(set) var isRefreshing = false

    init() {
        checks = LitterOnboardingCheckKind.allCases.map {
            LitterOnboardingCheck(kind: $0, status: .checking, detail: "Waiting to check.")
        }
    }

    func check(_ kind: LitterOnboardingCheckKind) -> LitterOnboardingCheck {
        checks.first { $0.kind == kind } ?? LitterOnboardingCheck(kind: kind, status: .checking, detail: "Waiting to check.")
    }

    func refresh(appModel: AppModel, appState: AppState) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        setAllChecking()

        if LitterPlatform.isLocalRuntimeReady {
            let shell = await IshFS.run("true")
            update(.shell, status: shell.exitCode == 0 ? .ready : .warning, detail: shell.exitCode == 0 ? "Commands can launch through the embedded iSH runtime." : shell.output.trimmingCharacters(in: .whitespacesAndNewlines))

            do {
                let entries = try await IshFS.listDirectory(path: HomeAnchor.path, includeHidden: true)
                update(.workspace, status: .ready, detail: "Listed \(entries.count) items under /root.")
            } catch {
                update(.workspace, status: .warning, detail: error.localizedDescription)
            }

            let pathCheck = await IshFS.run("[ -d /root ] && [ -d /usr/local/bin ] && [ -d /root/litter ]")
            update(.paths, status: pathCheck.exitCode == 0 ? .ready : .warning, detail: pathCheck.exitCode == 0 ? "/root, /root/litter, and /usr/local/bin are visible." : "/root/litter or /usr/local/bin is missing. Run the filesystem doctor from BuildKit settings if tools are unavailable.")
        } else {
            update(.shell, status: .warning, detail: "Local shell diagnostics are deferred until a local runtime feature is opened.")
            update(.workspace, status: .warning, detail: "Workspace checks are deferred until the local runtime is started.")
            update(.paths, status: .warning, detail: "Fakefs path checks are deferred until the local runtime is started.")
        }

        let connectedCount = appModel.snapshot?.servers.filter { $0.health == .connected }.count ?? 0
        if connectedCount > 0 {
            update(.runtime, status: .ready, detail: "\(connectedCount) conversation route\(connectedCount == 1 ? "" : "s") connected. Preferred route: \(appState.preferredChatRuntimeMode.title).")
        } else {
            update(.runtime, status: .warning, detail: "No connected route yet. Add a server or sign in from AI provider settings.")
        }

        let buildKit = await LitterBuildKit.shared.status()
        update(.buildKit, status: buildKit.isReadyForNativeBuilds ? .ready : .warning, detail: buildKit.readinessDetail)
        isRefreshing = false
    }

    private func setAllChecking() {
        checks = checks.map { LitterOnboardingCheck(kind: $0.kind, status: .checking, detail: "Checking...") }
    }

    private func update(_ kind: LitterOnboardingCheckKind, status: LitterOnboardingCheckStatus, detail: String) {
        guard let index = checks.firstIndex(where: { $0.kind == kind }) else { return }
        checks[index] = LitterOnboardingCheck(kind: kind, status: status, detail: detail.isEmpty ? "No diagnostic output." : detail)
    }
}

private enum LitterOnboardingDemoWorkspace {
    static let path = "/root/litter/welcome"

    static func createIfNeeded() async throws -> String {
        try await IshFS.createDirectoryIfNeeded(path: "/root/litter")
        try await IshFS.createDirectoryIfNeeded(path: path)
        try await writeIfMissing("\(path)/README.md", text: readme)
        try await writeIfMissing("\(path)/hello.swift", text: swiftSource)
        try await writeIfMissing("\(path)/LitterBuild.json", text: buildManifest)
        return path
    }

    private static func writeIfMissing(_ path: String, text: String) async throws {
        if await IshFS.exists(path: path) { return }
        try await IshFS.writeFile(path: path, data: Data(text.utf8), replaceExisting: false)
    }

    private static let readme = """
    # Welcome to Litter

    This folder was created by onboarding. It is safe to delete.

    Try these commands in the Litter terminal:

    ```sh
    pwd
    ls -la
    swift --version
    litter-swift-check hello.swift
    ```

    If BuildKit assets are installed, you can also try:

    ```sh
    swiftc hello.swift -o hello
    litter-swift-selftest
    ```
    """

    private static let swiftSource = """
    print("Swift is running inside Litter")
    """

    private static let buildManifest = """
    {
      "schemaVersion": 1,
      "name": "LitterWelcome",
      "bundleIdentifier": "com.example.litterwelcome",
      "deploymentTarget": "18.0",
      "sdk": "iphoneos",
      "product": "executable",
      "entrypoint": "hello.swift",
      "sources": ["hello.swift"],
      "resources": [],
      "output": "Builds/LitterWelcome"
    }
    """
}
