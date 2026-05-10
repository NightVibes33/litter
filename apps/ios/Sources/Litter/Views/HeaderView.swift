import SafariServices
import SwiftUI

struct HeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let thread: AppThreadSnapshot
    @State private var pulsing = false
    @AppStorage("fastMode") private var fastMode = false

    private var isRegularSurface: Bool {
        LitterPlatform.isRegularSurface(horizontalSizeClass: horizontalSizeClass)
    }

    private var server: AppServerSnapshot? {
        appModel.snapshot?.serverSnapshot(for: thread.key.serverId)
    }

    private var availableModels: [ModelInfo] {
        appModel.availableModels(for: thread.key.serverId)
    }

    private var headerPermissionPreset: AppThreadPermissionPreset {
        let approval = appState.launchApprovalPolicy(for: thread.key) ?? thread.effectiveApprovalPolicy
        let sandbox = appState.turnSandboxPolicy(for: thread.key) ?? thread.effectiveSandboxPolicy
        return threadPermissionPreset(approvalPolicy: approval, sandboxPolicy: sandbox)
    }

    var body: some View {
        Button {
            appState.showModelSelector.toggle()
        } label: {
            expandedHeaderLabel
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: isRegularSurface ? 320 : 240, alignment: .center)
        }
        .layoutPriority(-1)
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityIdentifier("header.modelPickerButton")
        .popover(
            isPresented: Binding(
                get: { appState.showModelSelector },
                set: { appState.showModelSelector = $0 }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            ConversationModelPickerPanel(thread: thread)
                .environment(appModel)
                .environment(appState)
                .presentationCompactAdaptation(.popover)
        }
        .task(id: thread.key) {
            await loadModelsIfNeeded()
        }
    }

    private var expandedHeaderLabel: some View {
        VStack(spacing: 2) {
            primaryHeaderRow
            secondaryHeaderRow
        }
    }

    private var primaryHeaderRow: some View {
        HStack(spacing: 6) {
            statusDot

            if fastMode {
                Image(systemName: "bolt.fill")
                    .font(LitterFont.styled(size: 10, weight: .semibold))
                    .foregroundColor(LitterTheme.warning)
            }

            Text(sessionModelLabel)
                .foregroundColor(LitterTheme.textPrimary)
                .allowsTightening(true)
            Text(sessionReasoningLabel)
                .foregroundColor(LitterTheme.textSecondary)
                .allowsTightening(true)
            Image(systemName: "chevron.down")
                .font(LitterFont.styled(size: 10, weight: .semibold))
                .foregroundColor(LitterTheme.textSecondary)
                .rotationEffect(.degrees(appState.showModelSelector ? 180 : 0))
        }
        .font(LitterFont.styled(size: 14, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(isRegularSurface ? 1.0 : 0.75)
    }

    private var secondaryHeaderRow: some View {
        HStack(spacing: 6) {
            Text(sessionDirectoryLabel)
                .font(LitterFont.styled(size: 11, weight: .semibold))
                .foregroundColor(LitterTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if thread.collaborationMode == .plan {
                Text("plan")
                    .font(LitterFont.styled(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LitterTheme.accent)
                    .clipShape(Capsule())
            }

            if headerPermissionPreset == .fullAccess {
                Image(systemName: "lock.open.fill")
                    .font(LitterFont.styled(size: 10, weight: .semibold))
                    .foregroundColor(LitterTheme.danger)
            }

            if server?.isIpcConnected == true, ExperimentalFeatures.shared.isEnabled(.ipc) {
                Text("IPC")
                    .font(LitterFont.styled(size: 11, weight: .bold))
                    .foregroundColor(LitterTheme.accentStrong)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LitterTheme.accentStrong.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 6, height: 6)
            .opacity(shouldPulse ? (pulsing ? 0.3 : 1.0) : 1.0)
            .animation(
                shouldPulse ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: pulsing
            )
            .onChange(of: shouldPulse) { _, pulse in
                pulsing = pulse
            }
    }

    private var shouldPulse: Bool {
        guard let transportState = server?.transportState else { return false }
        return transportState == .connecting || transportState == .unresponsive
    }

    private var statusDotColor: Color {
        guard let server else {
            return LitterTheme.textMuted
        }
        switch server.transportState {
        case .connecting, .unresponsive:
            return .orange
        case .connected:
            if server.hasIpc && server.ipcState == .disconnected && ExperimentalFeatures.shared.isEnabled(.ipc) {
                return .orange
            }
            if server.isLocal {
                switch server.account {
                case .chatgpt?, .apiKey?:
                    return LitterTheme.success
                case nil:
                    return LitterTheme.danger
                }
            }
            return server.account == nil ? .orange : LitterTheme.success
        case .disconnected:
            return LitterTheme.danger
        case .unknown:
            return LitterTheme.textMuted
        }
    }

    private var sessionModelLabel: String {
        let pendingModel = appState.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingModel.isEmpty {
            let modelLabel: String
            if let model = availableModels.first(where: {
                modelMatchesSelection(
                    $0,
                    pendingModel,
                    runtime: appState.selectedAgentRuntimeKind
                )
            }) {
                modelLabel = model.displayName
            } else {
                modelLabel = pendingModel
            }
            return "\(runtimeLabel(forSelection: pendingModel)) • \(modelLabel)"
        }

        let threadModel = thread.displayModelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelLabel = threadModel.isEmpty ? "litter" : threadModel
        return "\(runtimeLabel(forSelection: thread.model ?? thread.info.model)) • \(modelLabel)"
    }

    private func runtimeLabel(forSelection selection: String?) -> String {
        if isLocalGGUFModelSelection(selection) { return ChatRuntimeMode.localModel.shortTitle }
        if server?.isLocal == true { return ChatRuntimeMode.chatGPTAccount.shortTitle }
        return ChatRuntimeMode.computerBridge.shortTitle
    }

    private var sessionReasoningLabel: String {
        let pendingReasoning = appState.reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingReasoning.isEmpty { return pendingReasoning }

        let threadReasoning = thread.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !threadReasoning.isEmpty { return threadReasoning }

        // Fall back to the model's default reasoning effort from the loaded model list.
        let currentModel = (thread.model ?? thread.info.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let model = availableModels.first(where: {
            modelMatchesSelection(
                $0,
                currentModel,
                runtime: thread.agentRuntimeKind
            )
        }),
           !model.defaultReasoningEffort.wireValue.isEmpty {
            return model.defaultReasoningEffort.wireValue
        }

        return "default"
    }

    private var sessionDirectoryLabel: String {
        let currentDirectory = (thread.info.cwd ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentDirectory.isEmpty {
            let isLocal = appModel.isLocalServer(serverId: thread.key.serverId)
            return PathDisplay.display(currentDirectory, isLocal: isLocal)
        }

        return "~"
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: {
                let pending = appState.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pending.isEmpty { return pending }
                return currentThreadModelSelectionId
            },
            set: { appState.selectedModel = $0 }
        )
    }

    private var selectedAgentRuntimeKindBinding: Binding<AgentRuntimeKind?> {
        Binding(
            get: {
                let pending = appState.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pending.isEmpty { return appState.selectedAgentRuntimeKind }
                return currentThreadAgentRuntimeKind
            },
            set: { appState.selectedAgentRuntimeKind = $0 }
        )
    }

    private var currentThreadModelSelectionId: String {
        let currentModel = (thread.model ?? thread.info.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentModel.isEmpty else { return "" }
        return currentModel
    }

    private var currentThreadAgentRuntimeKind: AgentRuntimeKind? {
        thread.agentRuntimeKind
    }

    private var reasoningEffortBinding: Binding<String> {
        Binding(
            get: {
                let pending = appState.reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pending.isEmpty { return pending }
                return thread.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            },
            set: { appState.reasoningEffort = $0 }
        )
    }

    private func loadModelsIfNeeded() async {
        await appModel.loadConversationMetadataIfNeeded(serverId: thread.key.serverId)
    }
}

struct ConversationModelPickerPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    let thread: AppThreadSnapshot

    private var availableModels: [ModelInfo] {
        appModel.availableModels(for: thread.key.serverId)
    }

    var body: some View {
        InlineModelSelectorView(
            models: availableModels,
            selectedModel: selectedModelBinding,
            selectedAgentRuntimeKind: selectedAgentRuntimeKindBinding,
            reasoningEffort: reasoningEffortBinding,
            threadKey: thread.key,
            collaborationMode: thread.collaborationMode,
            effectiveApprovalPolicy: thread.effectiveApprovalPolicy,
            effectiveSandboxPolicy: thread.effectiveSandboxPolicy,
            showsBackground: false,
            onDismiss: {
                appState.showModelSelector = false
            }
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .task(id: thread.key) {
            await appModel.loadConversationMetadataIfNeeded(serverId: thread.key.serverId)
        }
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: {
                let pending = appState.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pending.isEmpty { return pending }
                return (thread.model ?? thread.info.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            },
            set: { appState.selectedModel = $0 }
        )
    }

    private var selectedAgentRuntimeKindBinding: Binding<AgentRuntimeKind?> {
        Binding(
            get: {
                let pending = appState.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pending.isEmpty { return appState.selectedAgentRuntimeKind }
                return thread.agentRuntimeKind
            },
            set: { appState.selectedAgentRuntimeKind = $0 }
        )
    }

    private var reasoningEffortBinding: Binding<String> {
        Binding(
            get: {
                let pending = appState.reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pending.isEmpty { return pending }
                return thread.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            },
            set: { appState.reasoningEffort = $0 }
        )
    }
}

struct ConversationToolbarControls: View {
    enum Control {
        case reload
        case info
    }

    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    let thread: AppThreadSnapshot
    let control: Control
    var onInfo: (() -> Void)?
    @State private var isReloading = false
    @State private var remoteAuthSession: RemoteAuthSession?

    private var server: AppServerSnapshot? {
        appModel.snapshot?.serverSnapshot(for: thread.key.serverId)
    }

    var body: some View {
        Group {
            switch control {
            case .reload:
                reloadButton
            case .info:
                infoButton
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .sheet(item: $remoteAuthSession) { session in
            InAppSafariView(url: session.url)
                .ignoresSafeArea()
        }
        .onChange(of: server?.account != nil) { _, isLoggedIn in
            if isLoggedIn {
                remoteAuthSession = nil
            }
        }
    }

    private var reloadButton: some View {
        Button {
            Task {
                isReloading = true
                defer { isReloading = false }
                if await handleRemoteLoginIfNeeded() {
                    return
                }
                if server?.account == nil {
                    appState.showSettings = true
                } else {
                    do {
                        let nextKey = try await appModel.refreshThreadIncludingTurns(key: thread.key)
                        appModel.store.setActiveThread(
                            key: nextKey
                        )
                    } catch {
                        // `AppModel` records the failure; keep the toolbar interaction quiet.
                    }
                }
            }
        } label: {
            reloadButtonLabel
        }
        .accessibilityIdentifier("header.reloadButton")
        .disabled(isReloading || server?.isConnected != true)
    }

    @ViewBuilder
    private var reloadButtonLabel: some View {
        if isReloading {
            ProgressView()
                .scaleEffect(0.7)
                .tint(LitterTheme.accent)
        } else {
            Image(systemName: "arrow.clockwise")
                .font(LitterFont.styled(size: 16, weight: .semibold))
                .foregroundColor(server?.isConnected == true ? LitterTheme.accent : LitterTheme.textMuted)
        }
    }

    private var infoButton: some View {
        Button {
            onInfo?()
        } label: {
            Image(systemName: "info.circle")
                .font(LitterFont.styled(size: 16, weight: .semibold))
                .foregroundColor(LitterTheme.accent)
        }
        .accessibilityIdentifier("header.infoButton")
    }

    private func handleRemoteLoginIfNeeded() async -> Bool {
        guard let server, !server.isLocal else {
            return false
        }
        guard server.account == nil else {
            return false
        }
        do {
            let authURL = try await appModel.client.startRemoteSshOauthLogin(
                serverId: server.serverId
            )
            if let url = URL(string: authURL) {
                await MainActor.run {
                    remoteAuthSession = RemoteAuthSession(url: url)
                }
            }
        } catch {}
        return true
    }
}

private struct RemoteAuthSession: Identifiable {
    let id = UUID()
    let url: URL
}

func modelMatchesSelection(
    _ model: ModelInfo,
    _ selection: String,
    runtime: AgentRuntimeKind? = nil
) -> Bool {
    let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if let runtime, model.agentRuntimeKind != runtime { return false }
    return model.id == trimmed || model.model == trimmed
}

struct InlineModelSelectorView: View {
    let models: [ModelInfo]
    @Binding var selectedModel: String
    @Binding var selectedAgentRuntimeKind: AgentRuntimeKind?
    @Binding var reasoningEffort: String
    var serverId: String? = nil
    /// `nil` indicates the view is being used before a thread exists (home
    /// composer). In that case, plan-mode selection is stored as a pending
    /// app-state preference that the caller applies after `startThread`.
    var threadKey: ThreadKey?
    var collaborationMode: AppModeKind = .default
    var effectiveApprovalPolicy: AppAskForApproval?
    var effectiveSandboxPolicy: AppSandboxPolicy?
    var showsBackground = true
    @Environment(AppModel.self) private var appModel
    @Environment(AppState.self) private var appState
    @AppStorage("fastMode") private var fastMode = false
    @State private var modelSearchQuery = ""
    @State private var modelSearchIndex = ModelSearchIndex()
    var onDismiss: () -> Void

    private var activeModelSearchIndex: ModelSearchIndex {
        if modelSearchIndex.isEmpty, !models.isEmpty {
            return ModelSearchIndex(models: models)
        }
        return modelSearchIndex
    }

    private var currentModel: ModelInfo? {
        if let match = modelsForSelectedRuntime.first(where: {
            modelMatchesSelection(
                $0,
                selectedModel,
                runtime: selectedAgentRuntimeKind
            )
        }) {
            return match
        }
        // When shown from the home composer, `selectedModel` may be empty
        // because the user hasn't picked yet. Fall back to the default model
        // within the selected runtime so the reasoning row stays consistent.
        return modelsForSelectedRuntime.first(where: { $0.isDefault }) ?? modelsForSelectedRuntime.first
    }

    /// Effective collaboration mode: live thread value when we have one,
    /// otherwise the pre-thread pending selection tracked on `appState`.
    private var effectiveCollaborationMode: AppModeKind {
        threadKey == nil ? appState.pendingCollaborationMode : collaborationMode
    }

    private var isFullAccess: Bool {
        let approval = appState.launchApprovalPolicy(for: threadKey) ?? effectiveApprovalPolicy
        let sandbox = appState.turnSandboxPolicy(for: threadKey) ?? effectiveSandboxPolicy
        return threadPermissionPreset(approvalPolicy: approval, sandboxPolicy: sandbox) == .fullAccess
    }

    private var currentServer: AppServerSnapshot? {
        guard let resolvedServerId = threadKey?.serverId ?? serverId else { return nil }
        return appModel.snapshot?.serverSnapshot(for: resolvedServerId)
    }

    private var localModels: [ModelInfo] {
        models.filter(isLocalGGUFModelInfo)
    }

    private var serverModels: [ModelInfo] {
        models.filter { !isLocalGGUFModelInfo($0) }
    }

    private var selectedRuntimeMode: ChatRuntimeMode {
        if isLocalGGUFModelSelection(selectedModel) { return .localModel }
        if threadKey == nil {
            let preferred = appState.preferredChatRuntimeMode
            if preferred == .localModel { return .localModel }
            if let currentServer {
                if preferred == .computerBridge, !currentServer.isLocal { return .computerBridge }
                if preferred == .chatGPTAccount, currentServer.isLocal { return .chatGPTAccount }
                return currentServer.isLocal ? .chatGPTAccount : .computerBridge
            }
            return preferred
        }
        return currentServer?.isLocal == true ? .chatGPTAccount : .computerBridge
    }

    private var modelsForSelectedRuntime: [ModelInfo] {
        switch selectedRuntimeMode {
        case .localModel:
            return localModels
        case .chatGPTAccount, .computerBridge:
            return serverModels
        }
    }

    var body: some View {
        let visibleModels = ModelSearchIndex(models: modelsForSelectedRuntime).results(matching: modelSearchQuery)

        VStack(spacing: 0) {
            runtimeSelector
            modelSearchField

            ScrollView {
                LazyVStack(spacing: 0) {
                    if models.isEmpty {
                        Text("Loading models...")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 24)
                    } else if visibleModels.isEmpty {
                        Text(emptyRuntimeMessage)
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 24)
                    }

                    let lastModelID = visibleModels.last?.id
                    ForEach(visibleModels) { model in
                        Button {
                            selectModel(model)
                            // Auto-dismiss only in the thread-scoped popover
                            // context. In the home sheet (no thread yet) we
                            // let the user pick a model AND change plan or
                            // permissions before hitting Done.
                            if threadKey != nil { onDismiss() }
                        } label: {
                            HStack {
                                ModelRuntimeIcon(kind: model.agentRuntimeKind)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(model.displayName)
                                            .litterFont(.footnote)
                                            .foregroundColor(LitterTheme.textPrimary)
                                        if model.isDefault {
                                            Text("default")
                                                .litterFont(.caption2, weight: .medium)
                                                .foregroundColor(LitterTheme.accent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(LitterTheme.accent.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(model.description)
                                        .litterFont(.caption2)
                                        .foregroundColor(LitterTheme.textSecondary)
                                }
                                Spacer()
                                if modelMatchesSelection(
                                    model,
                                    selectedModel,
                                    runtime: selectedAgentRuntimeKind
                                ) {
                                    Image(systemName: "checkmark")
                                        .litterFont(size: 12, weight: .medium)
                                        .foregroundColor(LitterTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        if model.id != lastModelID {
                            Divider().background(LitterTheme.separator).padding(.leading, 16)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let info = currentModel, !info.supportedReasoningEfforts.isEmpty {
                Divider().background(LitterTheme.separator).padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(info.supportedReasoningEfforts) { effort in
                            Button {
                                reasoningEffort = effort.reasoningEffort.wireValue
                                onDismiss()
                            } label: {
                                Text(effort.reasoningEffort.wireValue)
                                    .litterFont(.caption2, weight: .medium)
                                    .foregroundColor(effort.reasoningEffort.wireValue == reasoningEffort ? LitterTheme.textOnAccent : LitterTheme.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(effort.reasoningEffort.wireValue == reasoningEffort ? LitterTheme.accent : LitterTheme.surfaceLight)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            Divider().background(LitterTheme.separator).padding(.horizontal, 12)

            HStack(spacing: 6) {
                Button {
                    let current = effectiveCollaborationMode
                    let next: AppModeKind = current == .plan ? .default : .plan
                    if let threadKey {
                        Task {
                            try? await appModel.store.setThreadCollaborationMode(
                                key: threadKey, mode: next
                            )
                        }
                    } else {
                        appState.pendingCollaborationMode = next
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .litterFont(size: 9, weight: .semibold)
                        Text("Plan")
                            .litterFont(.caption2, weight: .medium)
                    }
                    .foregroundColor(effectiveCollaborationMode == .plan ? .black : LitterTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(effectiveCollaborationMode == .plan ? LitterTheme.accent : LitterTheme.surfaceLight)
                    .clipShape(Capsule())
                }

                Button {
                    fastMode.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .litterFont(size: 9, weight: .semibold)
                        Text("Fast")
                            .litterFont(.caption2, weight: .medium)
                    }
                    .foregroundColor(fastMode ? LitterTheme.textOnAccent : LitterTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(fastMode ? LitterTheme.warning : LitterTheme.surfaceLight)
                    .clipShape(Capsule())
                }

                Button {
                    if isFullAccess {
                        appState.setPermissions(approvalPolicy: "on-request", sandboxMode: "workspace-write", for: threadKey)
                    } else {
                        appState.setPermissions(approvalPolicy: "never", sandboxMode: "danger-full-access", for: threadKey)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isFullAccess ? "lock.open.fill" : "lock.fill")
                            .litterFont(size: 9, weight: .semibold)
                        Text(isFullAccess ? "Full Access" : "Supervised")
                            .litterFont(.caption2, weight: .medium)
                    }
                    .foregroundColor(isFullAccess ? LitterTheme.textOnAccent : LitterTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isFullAccess ? LitterTheme.danger : LitterTheme.surfaceLight)
                    .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(showsBackground ? LitterTheme.surface : Color.clear)
        .onAppear {
            modelSearchIndex = ModelSearchIndex(models: models)
        }
        .onChange(of: models) { _, newModels in
            modelSearchIndex = ModelSearchIndex(models: newModels)
        }
    }

    private var runtimeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Runtime")
                .litterFont(.caption2, weight: .bold)
                .foregroundStyle(LitterTheme.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                ForEach(ChatRuntimeMode.allCases) { mode in
                    runtimeButton(mode)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func runtimeButton(_ mode: ChatRuntimeMode) -> some View {
        let selected = selectedRuntimeMode == mode
        let available = runtimeIsAvailable(mode)
        return Button {
            selectRuntime(mode)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: mode.systemImage)
                        .litterFont(size: 11, weight: .semibold)
                    Text(mode.shortTitle)
                        .litterFont(.caption2, weight: .bold)
                        .lineLimit(1)
                }
                Text(runtimeSubtitle(mode))
                    .litterFont(size: 10, weight: .medium)
                    .lineLimit(2)
                    .foregroundStyle(selected ? LitterTheme.textOnAccent.opacity(0.82) : LitterTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? LitterTheme.accent : LitterTheme.surfaceLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(selected ? LitterTheme.textOnAccent : (available ? LitterTheme.textPrimary : LitterTheme.textMuted))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? LitterTheme.accentStrong.opacity(0.7) : LitterTheme.separator.opacity(0.8), lineWidth: 1)
            )
            .opacity(available ? 1 : 0.48)
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private var emptyRuntimeMessage: String {
        switch selectedRuntimeMode {
        case .chatGPTAccount:
            return "No ChatGPT models on this route"
        case .computerBridge:
            return "No bridge models on this route"
        case .localModel:
            return "No installed local models"
        }
    }

    private func runtimeIsAvailable(_ mode: ChatRuntimeMode) -> Bool {
        switch mode {
        case .chatGPTAccount:
            return currentServer?.isLocal == true && !serverModels.isEmpty
        case .computerBridge:
            return currentServer.map { !$0.isLocal && !serverModels.isEmpty } ?? false
        case .localModel:
            return !localModels.isEmpty
        }
    }

    private func runtimeSubtitle(_ mode: ChatRuntimeMode) -> String {
        switch mode {
        case .chatGPTAccount:
            if currentServer?.isLocal == true { return "Signed-in account" }
            return "Pick local ChatGPT server"
        case .computerBridge:
            if let currentServer, !currentServer.isLocal { return currentServer.displayName }
            return "Pick Mac/Windows/Linux"
        case .localModel:
            return localModels.isEmpty ? "Download GGUF first" : "Runs on this iPhone"
        }
    }

    private func selectRuntime(_ mode: ChatRuntimeMode) {
        appState.preferredChatRuntimeMode = mode
        switch mode {
        case .localModel:
            guard let model = localModels.first else { return }
            selectModel(model)
        case .chatGPTAccount, .computerBridge:
            guard let model = serverModels.first else { return }
            selectModel(model)
        }
    }

    private func selectModel(_ model: ModelInfo) {
        selectedModel = model.id
        selectedAgentRuntimeKind = model.agentRuntimeKind
        reasoningEffort = model.defaultReasoningEffort.wireValue
        if isLocalGGUFModelInfo(model) {
            appState.preferredChatRuntimeMode = .localModel
        } else if currentServer?.isLocal == true {
            appState.preferredChatRuntimeMode = .chatGPTAccount
        } else {
            appState.preferredChatRuntimeMode = .computerBridge
            if let resolvedServerId = threadKey?.serverId ?? serverId {
                appState.preferredBridgeServerId = resolvedServerId
            }
        }
    }

    private var modelSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LitterTheme.textMuted)
            TextField("Search models", text: $modelSearchQuery)
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textPrimary)
                .tint(LitterTheme.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !modelSearchQuery.isEmpty {
                Button { modelSearchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LitterTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct ModelSelectorSheet: View {
    let models: [ModelInfo]
    @Binding var selectedModel: String
    @Binding var selectedAgentRuntimeKind: AgentRuntimeKind?
    @Binding var reasoningEffort: String
    var serverId: String? = nil
    var threadKey: ThreadKey? = nil
    var collaborationMode: AppModeKind = .default
    var effectiveApprovalPolicy: AppAskForApproval?
    var effectiveSandboxPolicy: AppSandboxPolicy?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        InlineModelSelectorView(
            models: models,
            selectedModel: $selectedModel,
            selectedAgentRuntimeKind: $selectedAgentRuntimeKind,
            reasoningEffort: $reasoningEffort,
            serverId: serverId,
            threadKey: threadKey,
            collaborationMode: collaborationMode,
            effectiveApprovalPolicy: effectiveApprovalPolicy,
            effectiveSandboxPolicy: effectiveSandboxPolicy,
            onDismiss: { dismiss() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LitterTheme.surface.ignoresSafeArea())
    }
}

private struct ModelSearchIndex {
    private struct Row {
        let model: ModelInfo
        let searchableText: String
    }

    private static let maxResults = 80

    private var rows: [Row] = []

    var isEmpty: Bool {
        rows.isEmpty
    }

    init() {}

    init(models: [ModelInfo]) {
        rows = models.map { model in
            Row(
                model: model,
                searchableText: [
                    model.id,
                    model.model,
                    model.displayName,
                    model.description
                ]
                .joined(separator: "\n")
                .lowercased()
            )
        }
    }

    func results(matching query: String) -> [ModelInfo] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return Array(rows.prefix(Self.maxResults).map(\.model))
        }

        var matches: [ModelInfo] = []
        matches.reserveCapacity(min(Self.maxResults, rows.count))
        for row in rows where row.searchableText.contains(normalizedQuery) {
            matches.append(row.model)
            if matches.count == Self.maxResults {
                break
            }
        }
        return matches
    }
}

private struct ModelRuntimeIcon: View {
    let kind: AgentRuntimeKind

    var body: some View {
        Image(kind.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .padding(kind == .codex ? 0 : 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(kind == .codex ? Color.clear : Color.black.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(kind == .codex ? Color.clear : LitterTheme.textPrimary.opacity(0.3), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel(kind.displayLabel)
    }
}

#if DEBUG
#Preview("Header") {
    let appModel = LitterPreviewData.makeConversationAppModel()
    LitterPreviewScene(appModel: appModel) {
        HeaderView(thread: appModel.snapshot!.threads[0])
    }
}
#endif
