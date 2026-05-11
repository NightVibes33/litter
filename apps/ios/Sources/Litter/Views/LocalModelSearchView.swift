import SwiftUI

struct LocalModelSearchView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    @State private var capability = DeviceCapabilityProfile.current()
    @State private var query = ""
    @State private var results: [HuggingFaceModelSearchResult] = []
    @State private var customURL = ""
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var activeDownloadId: String?
    @State private var currentDownload: LocalModelDownloadCandidate?
    @State private var queuedDownloads: [LocalModelDownloadCandidate] = []
    @State private var lastFailedDownload: LocalModelDownloadCandidate?
    @State private var pendingDownload: LocalModelDownloadCandidate?
    @State private var localAgentModel: LocalModelRecord?
    @State private var selectedSearchResult: HuggingFaceModelSearchResult?

    var body: some View {
        List {
            deviceFitSection
            downloadProgressSection
            queuedDownloadsSection
            recommendedSection
            searchSection
            customURLSection
            installedSection
        }
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.inline)
        .task { capability = .current() }
        .refreshable {
            capability = .current()
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await search()
            }
        }
        .sheet(item: $localAgentModel) { model in
            LocalModelAgentView(model: model)
        }
        .sheet(item: $selectedSearchResult) { result in
            LocalModelDetailSheet(
                repository: result.modelId,
                capability: capability,
                activeDownloadId: activeDownloadId,
                queuedIds: Set(queuedDownloads.map(\.id)),
                onDownload: { candidate in
                    selectedSearchResult = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        pendingDownload = candidate
                    }
                }
            )
        }
        .sheet(item: $pendingDownload) { candidate in
            LocalModelDownloadConfirmationSheet(
                candidate: candidate,
                capability: capability,
                willQueue: activeDownloadId != nil,
                allowsCellularDownloads: providerStore.globalModelSettings.allowCellularDownloads,
                onCancel: { pendingDownload = nil },
                onConfirm: {
                    pendingDownload = nil
                    startOrQueue(candidate)
                }
            )
        }
    }

    private var deviceFitSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(capability.localInferenceTier.displayName, systemImage: capability.hasMetal ? "gpu" : "exclamationmark.triangle")
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundColor(capability.hasMetal ? LitterTheme.accent : LitterTheme.danger)
                Text(capability.localGenerationSummary)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                Text("Device fit is advisory. You can still download and set your own runtime context, batch, thread, and sampling values.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Device Fit")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var downloadProgressSection: some View {
        if let progress = providerStore.localModelDownloadProgress {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(progress.fileName)
                                .litterFont(.subheadline, weight: .semibold)
                                .foregroundColor(LitterTheme.textPrimary)
                                .lineLimit(2)
                            Text(downloadSubtitle(for: progress))
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textSecondary)
                            if let currentDownload {
                                Text(currentDownload.repositoryLabel)
                                    .litterFont(.caption)
                                    .foregroundColor(LitterTheme.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if progress.isFinished {
                            Button {
                                providerStore.clearLocalModelDownloadProgress()
                            } label: {
                                Label("Dismiss", systemImage: "xmark.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .foregroundColor(LitterTheme.textMuted)
                        } else {
                            Button {
                                providerStore.cancelLocalModelDownload()
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle.fill")
                                    .labelStyle(.iconOnly)
                            }
                            .foregroundColor(LitterTheme.danger)
                        }
                    }

                    if let fraction = progress.fractionCompleted {
                        ProgressView(value: fraction)
                            .tint(LitterTheme.accent)
                        Text("\(Int(fraction * 100))% - \(byteString(progress.bytesWritten)) of \(byteString(progress.totalBytes)) - \(speedString(progress.bytesPerSecond)) - \(etaString(progress))")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textMuted)
                    } else {
                        ProgressView()
                            .tint(LitterTheme.accent)
                        Text("\(byteString(progress.bytesWritten)) downloaded - \(speedString(progress.bytesPerSecond))")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textMuted)
                    }

                    if progress.phase == .failed, let lastFailedDownload {
                        Button {
                            startOrQueue(lastFailedDownload)
                        } label: {
                            Label("Retry Download", systemImage: "arrow.clockwise.circle.fill")
                        }
                        .litterFont(.caption, weight: .semibold)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(LitterTheme.surface.opacity(0.72))
            } header: {
                Text("Active Download")
                    .foregroundColor(LitterTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var queuedDownloadsSection: some View {
        if !queuedDownloads.isEmpty {
            Section {
                ForEach(queuedDownloads) { candidate in
                    HStack(spacing: 10) {
                        Image(systemName: "clock.badge.arrow.circlepath")
                            .foregroundColor(LitterTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.fileName)
                                .litterFont(.caption, weight: .semibold)
                                .foregroundColor(LitterTheme.textPrimary)
                                .lineLimit(1)
                            Text(candidate.repositoryLabel)
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Remove") {
                            queuedDownloads.removeAll { $0.id == candidate.id }
                        }
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.danger)
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
                }
            } header: {
                Text("Queued")
                    .foregroundColor(LitterTheme.textSecondary)
            }
        }
    }

    private var recommendedSection: some View {
        Section {
            ForEach(LocalModelCatalogItem.recommended) { item in
                let candidate = LocalModelDownloadCandidate.catalog(item)
                modelCard(
                    title: item.title,
                    subtitle: "\(item.subtitle) - \(item.displaySize)",
                    detail: item.warning ?? "Recommended shortcut. Review before download.",
                    modalities: item.modalities,
                    safety: capability.safety(forFileSize: item.sizeBytes, fileName: item.recommendedFileName),
                    downloadState: downloadState(for: candidate),
                    action: { pendingDownload = candidate }
                )
            }
        } header: {
            Text("Recommended")
                .foregroundColor(LitterTheme.textSecondary)
        } footer: {
            Text("Recommended models are just shortcuts. Search and direct GGUF downloads use the same download path.")
        }
    }

    private var searchSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField("Search Hugging Face GGUF", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                Button {
                    Task { await search() }
                } label: {
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(isLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if results.isEmpty, !isLoading, statusMessage == nil {
                Text("Search for GGUF repos, tap a result, then choose the exact quant/file on the detail page.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            ForEach(results) { result in
                Button {
                    selectedSearchResult = result
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "shippingbox.circle.fill")
                            .foregroundColor(LitterTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.modelId)
                                .litterFont(.subheadline, weight: .semibold)
                                .foregroundColor(LitterTheme.textPrimary)
                                .lineLimit(2)
                            Text("\(result.downloads ?? 0) downloads - \(result.likes ?? 0) likes - tap for model files")
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right.circle.fill")
                            .foregroundColor(LitterTheme.accent)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            if let statusMessage {
                Text(statusMessage)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Search")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var customURLSection: some View {
        Section {
            TextField("https://.../model.gguf", text: $customURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            Button {
                prepareCustomURLDownload()
            } label: {
                HStack {
                    Label("Review Direct GGUF URL", systemImage: "link.badge.plus")
                    Spacer()
                }
            }
            .disabled(URL(string: customURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Direct URL")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var installedSection: some View {
        Section {
            if providerStore.localModels.isEmpty {
                Text("No GGUF models installed.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            } else {
                ForEach(providerStore.localModels) { model in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.fileName)
                            .litterFont(.subheadline, weight: .semibold)
                            .foregroundColor(LitterTheme.textPrimary)
                            .lineLimit(2)
                        Text(installedSubtitle(for: model))
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                        Text(model.validationStatus.message)
                            .litterFont(.caption)
                            .foregroundColor(validationColor(for: model.validationStatus))
                        modalityLine(model.modalities)
                        HStack {
                            Button {
                                localAgentModel = model
                            } label: {
                                Label("Open Local Agent", systemImage: "bolt.horizontal.circle")
                            }
                            .disabled(!model.canRunLocally)
                            Button {
                                Task { await providerStore.validateLocalModel(model) }
                            } label: {
                                Label(providerStore.validatingLocalModelId == model.id ? "Verifying..." : "Verify", systemImage: "checkmark.seal")
                            }
                            .disabled(providerStore.validatingLocalModelId != nil)
                            if providerStore.validatingLocalModelId == model.id {
                                Button("Cancel") { providerStore.cancelLocalModelValidation() }
                                    .foregroundColor(LitterTheme.danger)
                            }
                            NavigationLink("Settings") {
                                LocalModelRuntimeSettingsView(model: model)
                            }
                        }
                        .litterFont(.caption, weight: .semibold)
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
                }
            }
        } header: {
            Text("Installed")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private func modelCard(
        title: String,
        subtitle: String,
        detail: String,
        modalities: [LocalModelModality],
        safety: (LocalModelSafety, String),
        downloadState: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundColor(LitterTheme.textPrimary)
                    Text(subtitle)
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textSecondary)
                    modalityLine(modalities)
                }
                Spacer()
                Button(action: action) {
                    Label(downloadState, systemImage: downloadState == "Queued" ? "clock" : "arrow.down.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(downloadState == "Downloading" || downloadState == "Queued")
                .foregroundColor(LitterTheme.accent)
            }
            Text(detail)
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
            Text(safety.1)
                .litterFont(.caption)
                .foregroundColor(color(for: safety.0))
        }
        .padding(.vertical, 4)
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func modalityLine(_ modalities: [LocalModelModality]) -> some View {
        Text(modalities.map(\.displayName).joined(separator: " - "))
            .litterFont(.caption)
            .foregroundColor(LitterTheme.accent)
    }

    private func installedSubtitle(for model: LocalModelRecord) -> String {
        var parts = [model.displaySize]
        if let nativeContextLength = model.nativeContextLength { parts.append("\(nativeContextLength) ctx") }
        parts.append(model.safety.displayName)
        parts.append(model.validationStatus.displayName)
        return parts.joined(separator: " - ")
    }

    private func validationColor(for status: LocalModelValidationStatus) -> Color {
        switch status {
        case .verified: return LitterTheme.success
        case .failed: return LitterTheme.danger
        case .validating: return LitterTheme.warning
        case .untested: return LitterTheme.textMuted
        }
    }

    private func color(for safety: LocalModelSafety) -> Color {
        switch safety {
        case .recommended: return LitterTheme.accent
        case .heavy: return LitterTheme.warning
        case .notRecommended, .pcRecommended: return LitterTheme.danger
        }
    }

    private func downloadSubtitle(for progress: LocalModelDownloadProgress) -> String {
        switch progress.phase {
        case .starting: return "Preparing secure download..."
        case .downloading: return "Downloading from \(progress.sourceURL.host ?? "remote host")"
        case .verifying: return progress.message ?? "Verifying model integrity..."
        case .installing: return progress.message ?? "Installing model..."
        case .finished: return "Installed. Ready to verify or run."
        case .cancelled: return "Download cancelled."
        case .failed: return progress.message ?? "Download failed."
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    private func speedString(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "calculating speed" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file))/s"
    }

    private func etaString(_ progress: LocalModelDownloadProgress) -> String {
        guard let seconds = progress.estimatedSecondsRemaining else { return "ETA calculating" }
        if seconds < 60 { return "ETA \(max(1, Int(seconds)))s" }
        return "ETA \(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
    }

    private func downloadState(for candidate: LocalModelDownloadCandidate) -> String {
        if activeDownloadId == candidate.id { return "Downloading" }
        if queuedDownloads.contains(where: { $0.id == candidate.id }) { return "Queued" }
        return "Download"
    }

    private func search() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }
        do {
            results = try await providerStore.searchHuggingFaceModels(query: query)
            statusMessage = results.isEmpty ? "No GGUF models found." : nil
        } catch {
            results = []
            statusMessage = error.localizedDescription
        }
    }

    private func prepareCustomURLDownload() {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }
        guard url.pathExtension.lowercased() == "gguf" else {
            statusMessage = "Only direct .gguf URLs can be imported as local models."
            return
        }
        pendingDownload = .direct(url)
    }

    private func startOrQueue(_ candidate: LocalModelDownloadCandidate) {
        if activeDownloadId != nil {
            if !queuedDownloads.contains(where: { $0.id == candidate.id }) {
                queuedDownloads.append(candidate)
                statusMessage = "Queued \(candidate.fileName)."
            }
            return
        }
        Task { await runDownload(candidate) }
    }

    private func runDownload(_ candidate: LocalModelDownloadCandidate) async {
        activeDownloadId = candidate.id
        currentDownload = candidate
        lastFailedDownload = nil
        statusMessage = "Downloading \(candidate.fileName)..."
        defer {
            activeDownloadId = nil
            currentDownload = nil
            if !queuedDownloads.isEmpty {
                let next = queuedDownloads.removeFirst()
                Task { await runDownload(next) }
            }
        }

        do {
            let record: LocalModelRecord
            switch candidate.source {
            case .catalog(let item):
                record = try await providerStore.downloadCatalogModel(item, capability: capability)
            case .huggingFace(let repository, let file, let details, let projector):
                record = try await providerStore.downloadHuggingFaceFile(
                    repository: repository,
                    file: file,
                    projector: projector,
                    architecture: details.gguf?.architecture,
                    nativeContextLength: details.gguf?.contextLength,
                    capability: capability
                )
            case .direct(let url):
                record = try await providerStore.downloadCustomModel(url: url, capability: capability)
            }
            statusMessage = "Installed \(record.fileName)."
        } catch is CancellationError {
            statusMessage = "Cancelled \(candidate.fileName)."
            lastFailedDownload = candidate
        } catch {
            statusMessage = error.localizedDescription
            lastFailedDownload = candidate
        }
    }
}

private struct LocalModelDownloadCandidate: Identifiable, Equatable {
    enum Source: Equatable {
        case catalog(LocalModelCatalogItem)
        case huggingFace(repository: String, file: HuggingFaceModelDetails.Sibling, details: HuggingFaceModelDetails, projector: HuggingFaceModelDetails.Sibling?)
        case direct(URL)
    }

    var source: Source

    var id: String {
        switch source {
        case .catalog(let item): return "catalog:\(item.id)"
        case .huggingFace(let repository, let file, _, _): return "hf:\(repository):\(file.rfilename)"
        case .direct(let url): return "direct:\(url.absoluteString)"
        }
    }

    var fileName: String {
        switch source {
        case .catalog(let item): return item.recommendedFileName
        case .huggingFace(_, let file, _, _): return file.rfilename
        case .direct(let url): return url.lastPathComponent.isEmpty ? "model.gguf" : url.lastPathComponent
        }
    }

    var title: String {
        switch source {
        case .catalog(let item): return item.title
        case .huggingFace(let repository, _, _, _): return repository
        case .direct: return "Direct GGUF URL"
        }
    }

    var repositoryLabel: String {
        switch source {
        case .catalog(let item): return item.repository
        case .huggingFace(let repository, _, _, _): return repository
        case .direct(let url): return url.host ?? "Direct URL"
        }
    }

    var sizeBytes: Int64 {
        switch source {
        case .catalog(let item): return item.sizeBytes
        case .huggingFace(_, let file, _, _): return file.lfs?.size ?? file.size ?? 0
        case .direct: return 0
        }
    }

    var architecture: String? {
        switch source {
        case .catalog(let item): return item.architecture
        case .huggingFace(_, _, let details, _): return details.gguf?.architecture
        case .direct: return nil
        }
    }

    var nativeContextLength: Int? {
        switch source {
        case .catalog: return nil
        case .huggingFace(_, _, let details, _): return details.gguf?.contextLength
        case .direct: return nil
        }
    }

    var modalities: [LocalModelModality] {
        switch source {
        case .catalog(let item): return item.modalities
        case .huggingFace(_, _, let details, let projector):
            if details.gguf?.architecture?.lowercased() == "gemma4", projector != nil { return [.text, .image, .audio, .video] }
            return projector == nil ? [.text] : [.text, .image]
        case .direct: return [.text]
        }
    }

    var sha256: String? {
        switch source {
        case .catalog: return nil
        case .huggingFace(_, let file, _, _): return file.lfs?.sha256
        case .direct: return nil
        }
    }

    var projectorFileName: String? {
        switch source {
        case .catalog(let item): return item.projectorFileName
        case .huggingFace(_, _, _, let projector): return projector?.rfilename
        case .direct: return nil
        }
    }

    static func catalog(_ item: LocalModelCatalogItem) -> LocalModelDownloadCandidate {
        LocalModelDownloadCandidate(source: .catalog(item))
    }

    static func huggingFace(
        repository: String,
        file: HuggingFaceModelDetails.Sibling,
        details: HuggingFaceModelDetails,
        projector: HuggingFaceModelDetails.Sibling?
    ) -> LocalModelDownloadCandidate {
        LocalModelDownloadCandidate(source: .huggingFace(repository: repository, file: file, details: details, projector: projector))
    }

    static func direct(_ url: URL) -> LocalModelDownloadCandidate {
        LocalModelDownloadCandidate(source: .direct(url))
    }
}

private struct LocalModelDownloadConfirmationSheet: View {
    let candidate: LocalModelDownloadCandidate
    let capability: DeviceCapabilityProfile
    let willQueue: Bool
    let allowsCellularDownloads: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(candidate.title)
                            .litterFont(.headline, weight: .semibold)
                            .foregroundColor(LitterTheme.textPrimary)
                            .textSelection(.enabled)
                        Text(candidate.fileName)
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                            .textSelection(.enabled)
                        Text(candidate.repositoryLabel)
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textMuted)
                            .textSelection(.enabled)
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.68))
                }

                Section("Download Facts") {
                    infoRow("Size", candidate.sizeBytes > 0 ? byteString(candidate.sizeBytes) : "Unknown until download starts")
                    infoRow("Architecture", candidate.architecture ?? "Unknown")
                    infoRow("Native Context", candidate.nativeContextLength.map { "\($0) tokens" } ?? "Unknown")
                    infoRow("Quant", DeviceCapabilityProfile.quantizationHint(from: candidate.fileName.lowercased()) ?? "Unknown")
                    infoRow("Modalities", candidate.modalities.map(\.displayName).joined(separator: " - "))
                    infoRow("Projector", candidate.projectorFileName ?? "None")
                    infoRow("Checksum", candidate.sha256 == nil ? "Unavailable" : "SHA256 available")
                    infoRow("Cellular", allowsCellularDownloads ? "Allowed" : "Wi-Fi only")
                }

                Section("Device Fit") {
                    let safety = capability.safety(forFileSize: candidate.sizeBytes, fileName: candidate.fileName)
                    Label(safety.0.displayName, systemImage: icon(for: safety.0))
                        .foregroundColor(color(for: safety.0))
                    Text(safety.1)
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textSecondary)
                    Text("This is a warning, not a lock. Runtime context and other settings remain user controlled.")
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textMuted)
                }

                Section {
                    Button {
                        onConfirm()
                    } label: {
                        Label(willQueue ? "Add to Queue" : "Start Download", systemImage: willQueue ? "text.badge.plus" : "arrow.down.circle.fill")
                    }
                    .foregroundColor(LitterTheme.accent)
                }
            }
            .navigationTitle("Review Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundColor(LitterTheme.textMuted)
            Spacer()
            Text(value)
                .foregroundColor(LitterTheme.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .litterFont(.caption)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    private func icon(for safety: LocalModelSafety) -> String {
        switch safety {
        case .recommended: return "checkmark.seal.fill"
        case .heavy: return "flame.fill"
        case .notRecommended, .pcRecommended: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for safety: LocalModelSafety) -> Color {
        switch safety {
        case .recommended: return LitterTheme.success
        case .heavy: return LitterTheme.warning
        case .notRecommended, .pcRecommended: return LitterTheme.danger
        }
    }
}

private struct LocalModelDetailSheet: View {
    @StateObject private var providerStore = AIProviderStore.shared
    let repository: String
    let capability: DeviceCapabilityProfile
    let activeDownloadId: String?
    let queuedIds: Set<String>
    let onDownload: (LocalModelDownloadCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var details: HuggingFaceModelDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(repository)
                            .litterFont(.headline, weight: .semibold)
                            .foregroundColor(LitterTheme.textPrimary)
                            .textSelection(.enabled)
                        if let details {
                            Text("\(details.downloads ?? 0) downloads - \(details.likes ?? 0) likes - architecture \(details.gguf?.architecture ?? "unknown")")
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textSecondary)
                        } else if isLoading {
                            ProgressView("Loading model details...")
                                .tint(LitterTheme.accent)
                        } else if let errorMessage {
                            Text(errorMessage)
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.danger)
                        }
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.68))
                }

                if let details {
                    if details.ggufFiles.isEmpty {
                        Section {
                            Label("No GGUF files exposed by this repo", systemImage: "exclamationmark.triangle")
                                .foregroundColor(LitterTheme.warning)
                            Text("Try a different result or paste a direct .gguf URL. Some Hugging Face repos hide files behind subfolders or gated access.")
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textSecondary)
                        }
                    } else {
                        Section("Downloadable GGUF Files") {
                            ForEach(details.ggufFiles) { file in
                                let candidate = LocalModelDownloadCandidate.huggingFace(
                                    repository: repository,
                                    file: file,
                                    details: details,
                                    projector: matchingProjector(for: file, in: details)
                                )
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.rfilename)
                                                .litterFont(.subheadline, weight: .semibold)
                                                .foregroundColor(LitterTheme.textPrimary)
                                                .textSelection(.enabled)
                                            Text(fileSubtitle(file, details: details))
                                                .litterFont(.caption)
                                                .foregroundColor(LitterTheme.textSecondary)
                                            if let projector = candidate.projectorFileName {
                                                Text("Projector: \(projector)")
                                                    .litterFont(.caption)
                                                    .foregroundColor(LitterTheme.accent)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Button {
                                            onDownload(candidate)
                                        } label: {
                                            Label(downloadState(for: candidate), systemImage: icon(for: candidate))
                                                .labelStyle(.iconOnly)
                                        }
                                        .disabled(activeDownloadId == candidate.id || queuedIds.contains(candidate.id))
                                        .foregroundColor(LitterTheme.accent)
                                    }
                                    if let warning = safetyWarning(for: file) {
                                        Text(warning)
                                            .litterFont(.caption)
                                            .foregroundColor(LitterTheme.warning)
                                    }
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(LitterTheme.surface.opacity(0.62))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Model Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: repository) { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            details = try await providerStore.fetchHuggingFaceModelDetails(repository: repository)
        } catch {
            details = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func matchingProjector(for file: HuggingFaceModelDetails.Sibling, in details: HuggingFaceModelDetails) -> HuggingFaceModelDetails.Sibling? {
        let lower = file.rfilename.lowercased()
        if lower.contains("gemma-4-e2b"), let match = details.projectorFiles.first(where: { $0.rfilename.lowercased().contains("gemma-4-e2b") }) {
            return match
        }
        if lower.contains("gemma-4-e4b"), let match = details.projectorFiles.first(where: { $0.rfilename.lowercased().contains("gemma-4-e4b") }) {
            return match
        }
        return details.projectorFiles.first
    }

    private func fileSubtitle(_ file: HuggingFaceModelDetails.Sibling, details: HuggingFaceModelDetails) -> String {
        let size = ByteCountFormatter.string(fromByteCount: file.lfs?.size ?? file.size ?? 0, countStyle: .file)
        let quant = DeviceCapabilityProfile.quantizationHint(from: file.rfilename.lowercased()) ?? "unknown quant"
        return "\(size) - \(quant) - \(details.gguf?.architecture ?? "unknown architecture")"
    }

    private func safetyWarning(for file: HuggingFaceModelDetails.Sibling) -> String? {
        let size = file.lfs?.size ?? file.size ?? 0
        let safety = capability.safety(forFileSize: size, fileName: file.rfilename)
        return safety.0 == .recommended ? nil : safety.1
    }

    private func downloadState(for candidate: LocalModelDownloadCandidate) -> String {
        if activeDownloadId == candidate.id { return "Downloading" }
        if queuedIds.contains(candidate.id) { return "Queued" }
        return "Download"
    }

    private func icon(for candidate: LocalModelDownloadCandidate) -> String {
        if activeDownloadId == candidate.id { return "arrow.down.circle.fill" }
        if queuedIds.contains(candidate.id) { return "clock.fill" }
        return "arrow.down.circle.fill"
    }
}
