import SwiftUI

struct ConversationComposerAttachSheet: View {
    let onPickPhotoLibrary: () -> Void
    let onChooseFile: (() -> Void)?
    let onChooseComputerFile: (() -> Void)?
    let onTakePhoto: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text("Attach")
                .litterFont(.headline, weight: .semibold)
                .foregroundColor(LitterTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onPickPhotoLibrary) {
                sheetButtonLabel("Photo Library", systemImage: "photo.on.rectangle")
            }

            if let onChooseFile {
                Button(action: onChooseFile) {
                    sheetButtonLabel("Files, Folder, ZIP or RAR", systemImage: "folder.badge.plus")
                }
            }

            if let onChooseComputerFile {
                Button(action: onChooseComputerFile) {
                    sheetButtonLabel("Computer File", systemImage: "desktopcomputer")
                }
            }

            if let onTakePhoto {
                Button(action: onTakePhoto) {
                    sheetButtonLabel("Take Photo", systemImage: "camera")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private func sheetButtonLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .litterFont(.body, weight: .medium)
                .foregroundColor(LitterTheme.accent)
                .frame(width: 20)

            Text(title)
                .litterFont(.body, weight: .medium)
                .foregroundColor(LitterTheme.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .modifier(GlassRoundedRectModifier(cornerRadius: 18))
    }
}

struct ConversationRemoteFilePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSearch: (String) async throws -> [FileSearchResult]
    let onAttach: (FileSearchResult) -> Void

    @State private var query: String
    @State private var results: [FileSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    init(
        title: String = "Computer Files",
        initialQuery: String = "",
        onSearch: @escaping (String) async throws -> [FileSearchResult],
        onAttach: @escaping (FileSearchResult) -> Void
    ) {
        self.title = title
        self.onSearch = onSearch
        self.onAttach = onAttach
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                resultsContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LitterTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LitterTheme.accent)
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: query) { _, next in
            scheduleSearch(next)
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LitterTheme.textMuted)
            TextField("Search files", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { runSearch(query) }
            if isLoading {
                ProgressView()
                    .tint(LitterTheme.accent)
                    .scaleEffect(0.82)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .modifier(GlassRoundedRectModifier(cornerRadius: 14))
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let errorMessage {
            stateText(errorMessage, color: .red)
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stateText("Type a file name or path")
        } else if isLoading && results.isEmpty {
            stateText("Searching...")
        } else if results.isEmpty {
            stateText("No matches")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(results.prefix(40).enumerated()), id: \.offset) { item in
                        RemoteFileResultRow(result: item.element) {
                            onAttach(item.element)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func stateText(_ text: String, color: Color = LitterTheme.textSecondary) -> some View {
        Text(text)
            .litterFont(.footnote)
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private func scheduleSearch(_ rawQuery: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            runSearch(rawQuery)
        }
    }

    private func runSearch(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        searchTask = nil
        guard !trimmed.isEmpty else {
            results = []
            isLoading = false
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        searchTask = Task { @MainActor in
            do {
                let matches = try await onSearch(trimmed)
                guard !Task.isCancelled else { return }
                results = matches
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct RemoteFileResultRow: View {
    let result: FileSearchResult
    let onAttach: () -> Void

    private var isDirectory: Bool {
        switch result.matchType {
        case .directory:
            return true
        case .file:
            return false
        }
    }

    private var iconName: String {
        isDirectory ? "folder.fill" : "doc.text"
    }

    private var title: String {
        let trimmed = result.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? result.path : trimmed
    }

    var body: some View {
        Button(action: onAttach) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .litterFont(.body, weight: .semibold)
                    .foregroundColor(isDirectory ? LitterTheme.accentStrong : LitterTheme.accent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundColor(LitterTheme.textPrimary)
                        .lineLimit(1)
                    Text(result.path)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundColor(LitterTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .foregroundColor(LitterTheme.accent)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .modifier(GlassRoundedRectModifier(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
