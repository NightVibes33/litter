import SwiftUI

struct LocalModelSearchView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    @State private var capability = DeviceCapabilityProfile.current()
    @State private var query = "gemma-4"
    @State private var results: [HuggingFaceModelSearchResult] = []
    @State private var selectedDetails: HuggingFaceModelDetails?
    @State private var selectedRepository: String?
    @State private var customURL = ""
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var activeDownloadId: String?

    var body: some View {
        List {
            recommendedSection
            searchSection
            customURLSection
            detailsSection
            installedSection
        }
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            capability = .current()
            if results.isEmpty {
                await search()
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
            Text("Recommended")
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
                    Task { await loadDetails(repository: result.modelId) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.modelId)
                            .litterFont(.subheadline)
                            .foregroundColor(LitterTheme.textPrimary)
                        Text("\(result.downloads ?? 0) downloads · \(result.likes ?? 0) likes")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                    }
                }
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
                        Text("\(model.displaySize) · \(model.safety.displayName)")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                        modalityLine(model.modalities)
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

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await providerStore.searchHuggingFaceModels(query: query)
            statusMessage = results.isEmpty ? "No GGUF models found." : nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadDetails(repository: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            selectedDetails = try await providerStore.fetchHuggingFaceModelDetails(repository: repository)
            selectedRepository = repository
        } catch {
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
