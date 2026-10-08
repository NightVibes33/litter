import Combine
import Foundation
import SwiftUI

struct LitterOnboardingState {
    static let currentVersion = 2
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
                AlleyBackdrop().ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    TabView(selection: $page) {
                        ForEach(LitterOnboardingPage.visibleCases) { page in
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
            ForEach(LitterOnboardingPage.visibleCases) { item in
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
            .disabled(page == LitterOnboardingPage.visibleCases.first)

            Button {
                if page == LitterOnboardingPage.visibleCases.last {
                    onFinish()
                } else {
                    moveNext()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(page == LitterOnboardingPage.visibleCases.last ? "Get Started" : "Continue")
                        .litterFont(.subheadline, weight: .semibold)
                    Image(systemName: page == LitterOnboardingPage.visibleCases.last ? "checkmark" : "chevron.right")
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
        .background(LitterTheme.surface.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(LitterTheme.accent.opacity(0.55)).frame(height: 1)
        }
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
                title: "Your coding workspace",
                detail: "Alley Cãt brings AI chat, local files, a shared terminal, remote machines, and iOS build tools into one mobile workspace."
            )
            featureGrid(welcomeFeatures)
        }
    }

    private var welcomeFeatures: [OnboardingFeature] {
        var features: [OnboardingFeature] = [
            .init(icon: "bubble.left.and.text.bubble.right", title: "AI threads", detail: "Start, resume, fork, and inspect coding sessions."),
            .init(icon: "folder", title: "Workspace files", detail: "Browse files in the local runtime workspace.")
        ]
        if ExperimentalFeatures.shared.isEnabled(.terminal) {
            features.append(.init(icon: "terminal", title: "Terminal", detail: "Enable Terminal in Advanced to show it on the home screen."))
        }
        if AppDistributionCapabilities.includesEmexDE {
            features.append(.init(icon: "hammer", title: "emexDE", detail: "Open the full embedded iOS development environment."))
        }
        return features
    }

    private var runtimePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            checkCard(readiness.check(.runtime))
            routeCard(
                icon: ChatRuntimeMode.chatGPTAccount.systemImage,
                title: "Account sign-in",
                detail: "Use the signed-in route for normal Alley Cãt conversations and hosted models.",
                actionTitle: "Open Account",
                action: { finishAndOpen { onOpenSettingsRoute("account") } }
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
                primaryTitle: ExperimentalFeatures.shared.isEnabled(.files) ? "Open Files" : "Enable Files in Advanced",
                primaryAction: { finishAndOpen { openFilesIfEnabled(HomeAnchor.path) } },
                secondaryTitle: ExperimentalFeatures.shared.isEnabled(.terminal) ? "Open Terminal" : nil,
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
                title: "emexDE development app",
                detail: "Open Nyxian for on-device projects and BuildKit for compiler settings in the full sideload build."
            )
            commandStrip(["swift --version", "litter-swift-check hello.swift", "litter-swift-selftest", "litter-build-status"])
            actionPanel(
                icon: "shippingbox.fill",
                title: "Nyxian and BuildKit",
                detail: "Use Nyxian for development and BuildKit to check compiler readiness.",
                primaryTitle: "Open emexDE",
                primaryAction: { finishAndOpen { onOpenSettingsRoute("emexDE") } },
                secondaryTitle: ExperimentalFeatures.shared.isEnabled(.terminal) ? "Terminal" : nil,
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
                .init(icon: "app.badge", title: "App icons", detail: "Choose an alternate icon in Icon Switcher.")
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
            .alleyPanel(cornerRadius: 12)

            actionPanel(
                icon: "sparkles",
                title: "Ready for your first turn",
                detail: "Open a project folder, pick the runtime you want, and ask Alley Cãt to inspect or change real files.",
                primaryTitle: "Start a Thread",
                primaryAction: { onFinish() },
                secondaryTitle: ExperimentalFeatures.shared.isEnabled(.files) ? "Open Files" : "Enable Files in Advanced",
                secondaryAction: { finishAndOpen { openFilesIfEnabled(HomeAnchor.path) } }
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
                    finishAndOpen { openFilesIfEnabled(LitterOnboardingDemoWorkspace.path) }
                }
                .buttonStyle(.bordered)
                .tint(LitterTheme.accent)
                .disabled(demoState != .created)
            }
        }
        .padding(14)
        .alleyPanel(cornerRadius: 12)
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
        .alleyPanel(tint: LitterTheme.accent, cornerRadius: 12)
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
                .alleyPanel(cornerRadius: 12)
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
        .alleyPanel(cornerRadius: 12)
    }

    private func checkCard(_ check: LitterOnboardingCheck) -> some View {
        checkRow(check)
            .padding(14)
            .alleyPanel(cornerRadius: 12)
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

    private func openFilesIfEnabled(_ path: String) {
        if ExperimentalFeatures.shared.isEnabled(.files) {
            onOpenFiles(path)
        } else {
            onOpenSettingsRoute("advanced")
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

    static var visibleCases: [LitterOnboardingPage] {
        allCases.filter { page in
            page != .buildKit || AppDistributionCapabilities.includesEmexDE
        }
    }

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Build with Alley Cãt"
        case .runtime: return "Pick your runtime"
        case .workspace: return "Files and terminal"
        case .buildKit: return "Nyxian and BuildKit"
        case .personalize: return "Make it yours"
        case .checklist: return "You are ready"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "A practical tour of the workspace you will use every day."
        case .runtime: return "Use hosted AI or connect a computer for local/private models."
        case .workspace: return "The bot, file browser, and terminal share the same iSH fakefs."
        case .buildKit: return "Development tools are included in the full sideload build."
        case .personalize: return "Tune the interface without losing the developer workflow."
        case .checklist: return "Live checks show what is ready and what needs setup."
        }
    }

    var previous: LitterOnboardingPage? {
        guard let index = Self.visibleCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.visibleCases[index - 1]
    }

    var next: LitterOnboardingPage? {
        guard let index = Self.visibleCases.firstIndex(of: self), index + 1 < Self.visibleCases.count else { return nil }
        return Self.visibleCases[index + 1]
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
            return "Create /root/alley-cat/welcome with a README, hello.swift, and a build manifest. Nothing is created unless you tap the button."
        case .creating:
            return "Creating files in the iSH fakefs without overwriting anything already there."
        case .created:
            return "Demo workspace is ready at /root/alley-cat/welcome."
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

    static var visibleCases: [LitterOnboardingCheckKind] {
        allCases.filter { kind in
            kind != .buildKit || AppDistributionCapabilities.includesEmexDE
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shell: return "Local shell bridge"
        case .workspace: return "File browser access"
        case .paths: return "Expected fakefs paths"
        case .runtime: return "Conversation route"
        case .buildKit: return "emexDE"
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
        checks = LitterOnboardingCheckKind.visibleCases.map {
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

        let shell = await IshFS.run("true")
        update(.shell, status: shell.exitCode == 0 ? .ready : .warning, detail: shell.exitCode == 0 ? "Commands can launch through the embedded iSH runtime." : shell.output.trimmingCharacters(in: .whitespacesAndNewlines))

        do {
            let entries = try await IshFS.listDirectory(path: HomeAnchor.path, includeHidden: true)
            update(.workspace, status: .ready, detail: "Listed \(entries.count) items under /root.")
        } catch {
            update(.workspace, status: .warning, detail: error.localizedDescription)
        }

        let pathCheck = await IshFS.run("[ -d /root ] && [ -d /usr/local/bin ] && [ -d /root/alley-cat ]")
        update(.paths, status: pathCheck.exitCode == 0 ? .ready : .warning, detail: pathCheck.exitCode == 0 ? "/root, /root/alley-cat, and /usr/local/bin are visible." : "/root/alley-cat or /usr/local/bin is missing. Open emexDE or Terminal if tools are unavailable.")

        let connectedCount = appModel.snapshot?.servers.filter { $0.health == .connected }.count ?? 0
        if connectedCount > 0 {
            update(.runtime, status: .ready, detail: "\(connectedCount) conversation route\(connectedCount == 1 ? "" : "s") connected. Preferred route: \(appState.preferredChatRuntimeMode.title).")
        } else {
            update(.runtime, status: .warning, detail: "No connected route yet. Add a server or sign in from Account settings.")
        }

        if AppDistributionCapabilities.includesEmexDE {
            let compiler = Bundle.main.privateFrameworksURL?
                .appendingPathComponent("CoreCompiler.framework/CoreCompiler")
            let bundled = compiler.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            update(.buildKit, status: bundled ? .ready : .warning, detail: bundled
                ? "CoreCompiler is included in this IPA. Open emexDE to prepare bundled support files and download the iPhoneOS SDK on first use. No separate compiler asset pack is required. Building and running your own apps may still require signing setup."
                : "The bundled CoreCompiler framework is missing. This installation cannot provide the full emexDE compiler; install the full sideload IPA.")
        }
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
    static let path = "/root/alley-cat/welcome"

    static func createIfNeeded() async throws -> String {
        try await IshFS.createDirectoryIfNeeded(path: "/root/alley-cat")
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
    # Welcome to Alley Cãt

    This folder was created by onboarding. It is safe to delete.

    Try these commands in the Alley Cãt terminal:

    ```sh
    pwd
    ls -la
    swift --version
    litter-swift-check hello.swift
    ```

    If native build assets are installed, you can also try:

    ```sh
    swiftc hello.swift -o hello
    litter-swift-selftest
    ```
    """

    private static let swiftSource = """
    print("Swift is running inside Alley Cãt")
    """

    private static let buildManifest = """
    {
      "schemaVersion": 1,
      "name": "AlleyCatWelcome",
      "bundleIdentifier": "com.example.alleycatwelcome",
      "deploymentTarget": "18.0",
      "sdk": "iphoneos",
      "product": "executable",
      "entrypoint": "hello.swift",
      "sources": ["hello.swift"],
      "resources": [],
      "output": "Builds/AlleyCatWelcome"
    }
    """
}
