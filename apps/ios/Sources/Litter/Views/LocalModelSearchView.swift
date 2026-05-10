import SwiftUI

struct LocalModelSearchView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    @State private var capability = DeviceCapabilityProfile.current()
    @State private var query = ""
    @State private var results: [HuggingFaceModelSearchResult] = []
    @State private var selectedDetails: HuggingFaceModelDetails?
    @State private var selectedRepository: String?
    @State private var customURL = ""
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var isLoadingDetails = false
    @State private var activeDownloadId: String?
    @State private var localAgentModel: LocalModelRecord?
    @State private var selectedSearchResult: HuggingFaceModelSearchResult?

    var body: some View {
        List {
            deviceFitSection
            downloadProgressSection
            recommendedSection
            searchSection
            detailsSection
            customURLSection
            installedSection
        }
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            capability = .current()
        }
        .sheet(item: $localAgentModel) { model in
            LocalModelAgentView(model: model)
        }
        .sheet(item: $selectedSearchResult) { result in
            LocalModelDetailSheet(
                repository: result.modelId,
                capability: capability,
                activeDownloadId: $activeDownloadId,
                statusMessage: $statusMessage
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
                if capability.recommendedContextTokens > 0 {
                    Text("Default local generation context: \(capability.recommendedContextTokens) tokens. Bigger GGUFs can still overheat or fail if storage is tight.")
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textMuted)
                }
                Text("Large models may still be better on an Ollama or LM Studio server, especially if Low Power Mode or thermal pressure is active.")
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
                                .lineLimit(1)
                            Text(downloadSubtitle(for: progress))
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textSecondary)
                        }
                        Spacer()
                        if !progress.isFinished {
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
                        Text("\(Int(fraction * 100))% · \(byteString(progress.bytesWritten)) of \(byteString(progress.totalBytes)) · \(speedString(progress.bytesPerSecond))")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textMuted)
                    } else {
                        ProgressView()
                            .tint(LitterTheme.accent)
                        Text("\(byteString(progress.bytesWritten)) downloaded · \(speedString(progress.bytesPerSecond))")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textMuted)
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

    private var recommendedSection: some View {
        Section {
            ForEach(LocalModelCatalogItem.recommended) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .litterFont(.subheadline, weight: .semibold)
                                .foregroundColor(LitterTheme.textPrimary)
                            Text("\(item.subtitle) · \(item.displaySize)")
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textSecondary)
                        }
                        Spacer()
                        Button {
                            Task { await downloadCatalog(item) }
                        } label: {
                            if activeDownloadId == item.id {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                        }
                        .disabled(activeDownloadId != nil)
                    }
                    modalityLine(item.modalities)
                    if let warning = item.warning {
                        Text(warning)
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.warning)
                    }
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Recommended Downloads")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var searchSection: some View {
        Section {
            HStack {
                TextField("Search Hugging Face GGUF", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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

            ForEach(results) { result in
                Button {
                    selectedSearchResult = result
                    Task { await loadDetails(repository: result.modelId) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.modelId)
                            .litterFont(.subheadline)
                            .foregroundColor(LitterTheme.textPrimary)
                        Text("\(result.downloads ?? 0) downloads · \(result.likes ?? 0) likes · tap for model details and downloads")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                    }
                    Spacer()
                    if selectedRepository == result.modelId, isLoadingDetails {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: selectedRepository == result.modelId ? "chevron.down.circle.fill" : "chevron.right.circle")
                            .foregroundColor(LitterTheme.accent)
                    }
                }
                .listRowBackground(selectedRepository == result.modelId ? LitterTheme.accent.opacity(0.14) : LitterTheme.surface.opacity(0.6))
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
                Task { await downloadCustomURL() }
            } label: {
                HStack {
                    Label("Download Direct GGUF URL", systemImage: "link.badge.plus")
                    Spacer()
                    if activeDownloadId == "custom" {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(activeDownloadId != nil || URL(string: customURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            .listRowBackground(LitterTheme.surface.opacity(0.6))
            if let statusMessage {
                Text(statusMessage)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Direct URL")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        if let selectedDetails, let selectedRepository {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedRepository)
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundColor(LitterTheme.textPrimary)
                    Text("\(selectedDetails.downloads ?? 0) downloads · architecture \(selectedDetails.gguf?.architecture ?? "unknown")")
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textSecondary)
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))

                if selectedDetails.ggufFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No downloadable GGUF files found", systemImage: "exclamationmark.triangle")
                            .litterFont(.subheadline, weight: .semibold)
                            .foregroundColor(LitterTheme.warning)
                        Text("Hugging Face returned this model page, but the API did not expose a .gguf sibling file. Try another result or paste a direct .gguf URL.")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
                }

                ForEach(selectedDetails.ggufFiles) { file in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.rfilename)
                                    .litterFont(.subheadline)
                                    .foregroundColor(LitterTheme.textPrimary)
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: file.lfs?.size ?? file.size ?? 0, countStyle: .file))
                                    .litterFont(.caption)
                                    .foregroundColor(LitterTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                Task { await downloadSearchFile(repository: selectedRepository, details: selectedDetails, file: file) }
                            } label: {
                                if activeDownloadId == file.rfilename {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                            }
                            .disabled(activeDownloadId != nil)
                        }
                        if selectedDetails.gguf?.architecture?.lowercased() == "gemma4", matchingProjector(for: file, in: selectedDetails) != nil {
                            modalityLine([.text, .image, .audio, .video])
                        }
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
                }
            } header: {
                Text("Model Files")
                    .foregroundColor(LitterTheme.textSecondary)
            }
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
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.fileName)
                            .litterFont(.subheadline)
                            .foregroundColor(LitterTheme.textPrimary)
                            .lineLimit(1)
                        Text("\(model.displaySize) · \(model.safety.displayName) · \(model.validationStatus.displayName)")
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
                                Label(providerStore.validatingLocalModelId == model.id ? "Verifying..." : "Verify Model", systemImage: "checkmark.seal")
                            }
                            .disabled(providerStore.validatingLocalModelId != nil)
                            if providerStore.validatingLocalModelId == model.id {
                                Button("Cancel") { providerStore.cancelLocalModelValidation() }
                                    .foregroundColor(LitterTheme.danger)
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

    private func modalityLine(_ modalities: [LocalModelModality]) -> some View {
        Text(modalities.map(\.displayName).joined(separator: " · "))
            .litterFont(.caption)
            .foregroundColor(LitterTheme.accent)
    }

    private func validationColor(for status: LocalModelValidationStatus) -> Color {
        switch status {
        case .verified: return LitterTheme.success
        case .failed: return LitterTheme.danger
        case .validating: return LitterTheme.warning
        case .untested: return LitterTheme.textMuted
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

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await providerStore.searchHuggingFaceModels(query: query)
            statusMessage = results.isEmpty ? "No GGUF models found." : nil
            selectedDetails = nil
            selectedRepository = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadDetails(repository: String) async {
        selectedRepository = repository
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        do {
            selectedDetails = try await providerStore.fetchHuggingFaceModelDetails(repository: repository)
            statusMessage = selectedDetails?.ggufFiles.isEmpty == true ? "No downloadable GGUF files found for \(repository)." : nil
        } catch {
            selectedDetails = nil
            statusMessage = error.localizedDescription
        }
    }

    private func downloadCatalog(_ item: LocalModelCatalogItem) async {
        activeDownloadId = item.id
        statusMessage = "Downloading \(item.title)..."
        defer { activeDownloadId = nil }
        do {
            let record = try await providerStore.downloadCatalogModel(item, capability: capability)
            statusMessage = "Installed \(record.fileName)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func downloadSearchFile(repository: String, details: HuggingFaceModelDetails, file: HuggingFaceModelDetails.Sibling) async {
        activeDownloadId = file.rfilename
        statusMessage = "Downloading \(file.rfilename)..."
        defer { activeDownloadId = nil }
        do {
            let record = try await providerStore.downloadHuggingFaceFile(
                repository: repository,
                file: file,
                projector: matchingProjector(for: file, in: details),
                architecture: details.gguf?.architecture,
                capability: capability
            )
            statusMessage = "Installed \(record.fileName)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func downloadCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }
        activeDownloadId = "custom"
        statusMessage = "Downloading \(url.lastPathComponent)..."
        defer { activeDownloadId = nil }
        do {
            let record = try await providerStore.downloadCustomModel(url: url, capability: capability)
            statusMessage = "Installed \(record.fileName)."
        } catch {
            statusMessage = error.localizedDescription
        }
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
}


private struct LocalModelDetailSheet: View {
    @StateObject private var providerStore = AIProviderStore.shared
    let repository: String
    let capability: DeviceCapabilityProfile
    @Binding var activeDownloadId: String?
    @Binding var statusMessage: String?
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
                            Text("\(details.downloads ?? 0) downloads · \(details.likes ?? 0) likes · architecture \(details.gguf?.architecture ?? "unknown")")
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
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.rfilename)
                                                .litterFont(.subheadline, weight: .semibold)
                                                .foregroundColor(LitterTheme.textPrimary)
                                                .textSelection(.enabled)
                                            Text(fileSubtitle(file, details: details))
                                                .litterFont(.caption)
                                                .foregroundColor(LitterTheme.textSecondary)
                                        }
                                        Spacer()
                                        Button {
                                            Task { await download(file, details: details) }
                                        } label: {
                                            if activeDownloadId == file.rfilename {
                                                ProgressView().scaleEffect(0.8)
                                            } else {
                                                Label("Download", systemImage: "arrow.down.circle.fill")
                                                    .labelStyle(.iconOnly)
                                            }
                                        }
                                        .disabled(activeDownloadId != nil)
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

    private func download(_ file: HuggingFaceModelDetails.Sibling, details: HuggingFaceModelDetails) async {
        activeDownloadId = file.rfilename
        statusMessage = "Downloading \(file.rfilename)..."
        defer { activeDownloadId = nil }
        do {
            let record = try await providerStore.downloadHuggingFaceFile(
                repository: repository,
                file: file,
                projector: matchingProjector(for: file, in: details),
                architecture: details.gguf?.architecture,
                capability: capability
            )
            statusMessage = "Installed \(record.fileName)."
        } catch {
            statusMessage = error.localizedDescription
        }
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
        return "\(size) · \(quant) · \(details.gguf?.architecture ?? "unknown architecture")"
    }

    private func safetyWarning(for file: HuggingFaceModelDetails.Sibling) -> String? {
        let size = file.lfs?.size ?? file.size ?? 0
        let safety = capability.safety(forFileSize: size, fileName: file.rfilename)
        return safety.0 == .recommended ? nil : safety.1
    }
}
