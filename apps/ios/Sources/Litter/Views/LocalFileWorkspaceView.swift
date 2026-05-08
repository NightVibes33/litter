import SwiftUI
import Observation
import UniformTypeIdentifiers

struct LocalFileWorkspaceView: View {
    @State private var model = LocalFileWorkspaceModel()
    @State private var showImporter = false
    @State private var showNewFile = false
    @State private var showNewFolder = false
    @State private var draftName = ""
    @State private var renameTarget: LocalFileEntry?
    @State private var renameText = ""
    @State private var deleteTarget: LocalFileEntry?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LitterTheme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    pathBar
                    Divider().overlay(LitterTheme.surfaceLight.opacity(0.4))
                    content
                }
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Import file")
                    Menu {
                        Button("New File", systemImage: "doc.badge.plus") { draftName = ""; showNewFile = true }
                        Button("New Folder", systemImage: "folder.badge.plus") { draftName = ""; showNewFolder = true }
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.reload() } }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(LitterTheme.accent)
                    }
                }
            }
            .task { await model.loadInitial() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                Task { await handleImport(result) }
            }
            .alert("New File", isPresented: $showNewFile) {
                TextField("filename.swift", text: $draftName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { draftName = "" }
                Button("Create") { Task { await create(kind: .file) } }
            } message: {
                Text("Create a text file in the current iSH directory.")
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("folder-name", text: $draftName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { draftName = "" }
                Button("Create") { Task { await create(kind: .directory) } }
            }
            .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $renameText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") { Task { await renameSelected() } }
            }
            .alert("Delete Item", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("Cancel", role: .cancel) { deleteTarget = nil }
                Button("Delete", role: .destructive) { Task { await deleteSelected() } }
            } message: {
                Text("This removes \(deleteTarget?.name ?? "this item") from the iSH filesystem.")
            }
            .alert("Files", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .sheet(item: $model.openFile) { file in
                LocalTextFileEditorView(file: file) { saved in
                    if saved { Task { await model.reload() } }
                }
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 10) {
            Button { Task { await model.navigateUp() } } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 34, height: 34)
            }
            .disabled(!model.canNavigateUp || model.isLoading)
            .buttonStyle(.plain)
            .modifier(GlassCapsuleModifier(interactive: model.canNavigateUp && !model.isLoading))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(model.displayPath)
                    .litterMonoFont(size: 13, weight: .medium)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.vertical, 8)
            }

            Toggle(isOn: $model.showHidden) {
                Image(systemName: "eye")
            }
            .labelsHidden()
            .tint(LitterTheme.accent)
            .onChange(of: model.showHidden) { _, _ in Task { await model.reload() } }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView("Loading files...")
                .foregroundStyle(LitterTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(LitterTheme.warning)
                Text(error)
                    .litterFont(.footnote)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await model.reload() } }
                    .foregroundStyle(LitterTheme.accent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(LitterTheme.textMuted)
                Text("This folder is empty")
                    .litterFont(.headline)
                    .foregroundStyle(LitterTheme.textPrimary)
                Text("Create a file, create a folder, or import a document from iOS Files.")
                    .litterFont(.footnote)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.entries) { entry in
                Button {
                    Task { await model.open(entry) }
                } label: {
                    LocalFileRow(entry: entry)
                }
                .buttonStyle(.plain)
                .listRowBackground(LitterTheme.surface.opacity(0.58))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteTarget = entry } label: { Label("Delete", systemImage: "trash") }
                    Button { renameTarget = entry; renameText = entry.name } label: { Label("Rename", systemImage: "pencil") }
                        .tint(.blue)
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { renameTarget = entry; renameText = entry.name }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = entry }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func create(kind: LocalFileEntry.Kind) async {
        let name = sanitizedName(draftName)
        draftName = ""
        guard !name.isEmpty else { return }
        do {
            try await model.create(name: name, kind: kind)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func renameSelected() async {
        guard let target = renameTarget else { return }
        let name = sanitizedName(renameText)
        renameTarget = nil
        guard !name.isEmpty, name != target.name else { return }
        do {
            try await model.rename(target, to: name)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteSelected() async {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        do {
            try await model.delete(target)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            for url in urls {
                try await model.importFile(from: url)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func sanitizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
    }
}

private struct LocalFileRow: View {
    let entry: LocalFileEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .directory ? "folder.fill" : entry.iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(entry.kind == .directory ? LitterTheme.accent : LitterTheme.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .litterFont(.subheadline, weight: .medium)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .lineLimit(1)
                Text(entry.detailText)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(LitterTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: entry.kind == .directory ? "chevron.right" : "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LitterTheme.textMuted)
        }
        .padding(.vertical, 8)
    }
}

private struct LocalTextFileEditorView: View {
    let file: LocalFileEntry
    let onClose: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var hasUnsavedChanges = false

    var body: some View {
        NavigationStack {
            ZStack {
                LitterTheme.backgroundGradient.ignoresSafeArea()
                if isLoading {
                    ProgressView("Opening...")
                        .foregroundStyle(LitterTheme.textSecondary)
                } else {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(LitterTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(LitterTheme.surface.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(12)
                        .onChange(of: text) { _, _ in hasUnsavedChanges = true }
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss(); onClose(false) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().scaleEffect(0.8) } else { Text("Save") }
                    }
                    .disabled(isLoading || isSaving || !hasUnsavedChanges)
                    .foregroundStyle(LitterTheme.accent)
                }
            }
            .task { await load() }
            .alert("Editor", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load() async {
        isLoading = true
        do {
            text = try await IshFS.readTextFile(path: file.path, maxBytes: 1_000_000)
            hasUnsavedChanges = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        do {
            try await IshFS.writeTextFile(path: file.path, text: text)
            hasUnsavedChanges = false
            onClose(true)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

@MainActor
@Observable
private final class LocalFileWorkspaceModel {
    var currentPath = HomeAnchor.path
    var entries: [LocalFileEntry] = []
    var isLoading = false
    var errorMessage: String?
    var showHidden = false
    var openFile: LocalFileEntry?

    var displayPath: String {
        currentPath == HomeAnchor.path ? "~" : currentPath.replacingOccurrences(of: HomeAnchor.path, with: "~")
    }

    var canNavigateUp: Bool {
        !currentPath.isEmpty && currentPath != "/" && currentPath != HomeAnchor.path
    }

    func loadInitial() async {
        await reload(path: currentPath)
    }

    func reload() async {
        await reload(path: currentPath)
    }

    func reload(path: String) async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await IshFS.listDirectory(path: path, includeHidden: showHidden)
            currentPath = path
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func open(_ entry: LocalFileEntry) async {
        switch entry.kind {
        case .directory:
            await reload(path: entry.path)
        case .file:
            openFile = entry
        }
    }

    func navigateUp() async {
        guard canNavigateUp else { return }
        let parent = RemotePath.parse(path: currentPath).parent().asString()
        await reload(path: parent.isEmpty ? "/" : parent)
    }

    func create(name: String, kind: LocalFileEntry.Kind) async throws {
        let target = RemotePath.parse(path: currentPath).join(name: name).asString()
        switch kind {
        case .directory:
            try await IshFS.createDirectory(path: target)
        case .file:
            try await IshFS.writeTextFile(path: target, text: "")
        }
        await reload()
    }

    func rename(_ entry: LocalFileEntry, to name: String) async throws {
        let target = RemotePath.parse(path: currentPath).join(name: name).asString()
        try await IshFS.rename(path: entry.path, to: target)
        await reload()
    }

    func delete(_ entry: LocalFileEntry) async throws {
        try await IshFS.delete(path: entry.path)
        await reload()
    }

    func importFile(from url: URL) async throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
        let target = RemotePath.parse(path: currentPath).join(name: url.lastPathComponent).asString()
        try await IshFS.writeFile(path: target, data: data)
        await reload()
    }
}

struct LocalFileEntry: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case file
        case directory
    }

    let kind: Kind
    let name: String
    let path: String
    let size: Int64

    var id: String { path }

    var detailText: String {
        kind == .directory ? "folder" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var iconName: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "rs", "js", "ts", "tsx", "jsx", "py", "sh", "rb", "go", "c", "h", "m", "mm", "cpp", "json", "yml", "yaml", "toml", "md":
            return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp", "svg":
            return "photo"
        case "zip", "gz", "tar", "xz":
            return "archivebox"
        default:
            return "doc.text"
        }
    }
}
