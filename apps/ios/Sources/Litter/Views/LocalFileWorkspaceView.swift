import SwiftUI
import Observation
import UniformTypeIdentifiers
import UIKit

struct LocalFileWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("litterSettingsRequestedRoute") private var settingsRequestedRoute = ""
    @AppStorage("litterTerminalInitialDirectory") private var terminalInitialDirectory = HomeAnchor.path
    @AppStorage(LitterOnboardingState.fileWorkspaceInitialDirectoryKey) private var fileWorkspaceInitialDirectory = HomeAnchor.path

    @State private var model = LocalFileWorkspaceModel()
    @State private var showImporter = false
    @State private var showNewFile = false
    @State private var showNewFolder = false
    @State private var draftName = ""
    @State private var renameTarget: LocalFileEntry?
    @State private var renameText = ""
    @State private var moveTarget: LocalFileEntry?
    @State private var moveDestination = ""
    @State private var deleteTarget: LocalFileEntry?
    @State private var showDeleteSelection = false
    @State private var alertMessage: String?
    @State private var previewTarget: LocalFileEntry?
    @State private var inspectorTarget: LocalFileEntry?
    @State private var sharePayload: LocalFileSharePayload?
    @State private var commandOutput: LocalCommandOutput?

    @StateObject private var taskBag = ViewTaskBag()
    var body: some View {
        sheetLayer
    }

    private var sheetLayer: some View {
        alertLayer
            .sheet(item: $previewTarget) { file in
                previewSheet(for: file)
            }
            .sheet(item: $inspectorTarget) { file in
                LocalFileInspectorSheet(
                    file: file,
                    onPreview: { previewTarget = file },
                    onEdit: { model.openFile = file },
                    onCopyPath: { copyPath(file.path) },
                    onCopyBotMention: { copyBotMention(file) },
                    onOpenTerminal: { openTerminal(at: terminalPath(for: file)) }
                )
            }
            .sheet(item: $model.openFile) { file in
                LocalTextFileEditorView(file: file) { saved in
                    if saved { taskBag.run { await model.reload() } }
                }
            }
            .sheet(item: $sharePayload) { payload in
                LocalFileActivitySheet(urls: payload.urls)
            }
            .sheet(item: $commandOutput) { output in
                LocalCommandOutputSheet(output: output)
            }
    }

    private var alertLayer: some View {
        messageAlertLayer
    }

    private var messageAlertLayer: some View {
        deleteAlertLayer
            .alert("Files", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
    }

    private var deleteAlertLayer: some View {
        renameMoveAlertLayer
            .alert("Delete Item", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("Cancel", role: .cancel) { deleteTarget = nil }
                Button("Delete", role: .destructive) { taskBag.run { await deleteSelected() } }
            } message: {
                Text("This removes \(deleteTarget?.name ?? "this item") from the iSH filesystem.")
            }
            .alert("Delete Selected Items", isPresented: $showDeleteSelection) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { taskBag.run { await deleteSelection() } }
            } message: {
                Text("This removes \(model.selectedPaths.count) selected item(s) from the iSH filesystem.")
            }
    }

    private var renameMoveAlertLayer: some View {
        creationAlertLayer
            .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $renameText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") { taskBag.run { await renameSelected() } }
            }
            .alert("Move Item", isPresented: Binding(get: { moveTarget != nil }, set: { if !$0 { moveTarget = nil } })) {
                TextField("Destination folder", text: $moveDestination)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { moveTarget = nil }
                Button("Move") { taskBag.run { await moveSelected() } }
            } message: {
                Text("Move \(moveTarget?.name ?? "this item") to another iSH folder. You can use ~ for /root.")
            }
    }

    private var creationAlertLayer: some View {
        importerLayer
            .alert("New File", isPresented: $showNewFile) {
                TextField("filename.swift", text: $draftName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { draftName = "" }
                Button("Create") { taskBag.run { await create(kind: .file) } }
            } message: {
                Text("Create a text file in the current iSH directory.")
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("folder-name", text: $draftName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { draftName = "" }
                Button("Create") { taskBag.run { await create(kind: .directory) } }
            }
    }

    private var importerLayer: some View {
        chromeLayer
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
                taskBag.run { await handleImport(result) }
            }
    }

    private var chromeLayer: some View {
        rootLayer
            .navigationTitle(model.isSelecting ? "\(model.selectedPaths.count) Selected" : "Files")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Files")
            .toolbar { toolbarContent }
            .task {
                let initialPath = fileWorkspaceInitialDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? HomeAnchor.path : fileWorkspaceInitialDirectory
                fileWorkspaceInitialDirectory = HomeAnchor.path
                await model.loadInitial(path: initialPath)
            }
            .onChange(of: model.showHidden) { _, _ in taskBag.run { await model.reload() } }
            .onDisappear { taskBag.cancelAll() }
    }

    private var rootLayer: some View {
        ZStack {
            LitterTheme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                pathBar
                Divider().overlay(LitterTheme.surfaceLight.opacity(0.4))
                content
            }
        }
    }


    private func previewSheet(for file: LocalFileEntry) -> some View {
        LocalFilePreviewSheet(
            file: file,
            onEdit: { openEditorAfterPreview(file) },
            onShare: { taskBag.run { await share([file]) } },
            onCopyPath: { copyPath(file.path) }
        )
    }

    private func openEditorAfterPreview(_ file: LocalFileEntry) {
        previewTarget = nil
        taskBag.run {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            model.openFile = file
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { model.clearSelection() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { copySelectedPaths() } label: { Image(systemName: "doc.on.doc") }
                    .disabled(model.selectedPaths.isEmpty)
                    .accessibilityLabel("Copy selected paths")
                Button { taskBag.run { await share(model.selectedEntries) } } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(model.selectedPaths.isEmpty)
                    .accessibilityLabel("Share selected")
                Button(role: .destructive) { showDeleteSelection = true } label: { Image(systemName: "trash") }
                    .disabled(model.selectedPaths.isEmpty)
                    .accessibilityLabel("Delete selected")
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Import file")
                Menu {
                    Button("New File", systemImage: "doc.badge.plus") { draftName = ""; showNewFile = true }
                    Button("New Folder", systemImage: "folder.badge.plus") { draftName = ""; showNewFolder = true }
                    Divider()
                    Button("Refresh", systemImage: "arrow.clockwise") { taskBag.run { await model.reload() } }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(LitterTheme.accent)
                }
                Menu {
                    Picker("View", selection: $model.viewMode) {
                        ForEach(LocalFileViewMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    Picker("Sort By", selection: $model.sort) {
                        ForEach(LocalFileSort.allCases) { sort in
                            Label(sort.title, systemImage: sort.systemImage).tag(sort)
                        }
                    }
                    Picker("Filter", selection: $model.activeFilter) {
                        ForEach(LocalFileFilter.allCases) { filter in
                            Label(filter.title, systemImage: filter.systemImage).tag(filter)
                        }
                    }
                    Toggle("Show Hidden Files", isOn: $model.showHidden)
                    Toggle("Advanced Locations", isOn: $model.showAdvancedLocations)
                    if !model.trimmedSearchQuery.isEmpty {
                        Button("Search Recursively", systemImage: "magnifyingglass.circle") { taskBag.run { await runRecursiveSearch() } }
                    }
                    Button("Find Large Files", systemImage: "internaldrive") { taskBag.run { await runLargeFileSearch() } }
                    Button("Folder Tree", systemImage: "list.bullet.indent") { taskBag.run { await runTreeSnapshot() } }
                    Button("Git Status Here", systemImage: "point.3.connected.trianglepath.dotted") { taskBag.run { await runGitStatus() } }
                    if model.hasLitterBuildManifest {
                        Divider()
                        Button("Swift Build", systemImage: "hammer") { taskBag.run { await runSwiftBuild() } }
                        Button("Build IPA", systemImage: "shippingbox") { taskBag.run { await runIPABuild() } }
                    }
                    Divider()
                    Button("Build Status", systemImage: "chart.bar.doc.horizontal") { taskBag.run { await runBuildStatus() } }
                    Button("Filesystem Doctor", systemImage: "stethoscope") { taskBag.run { await runFilesystemDoctor() } }
                    Button("Create LitterBuild.json", systemImage: "doc.badge.gearshape") { taskBag.run { await createLitterBuildManifest() } }
                    Divider()
                    Button("Select", systemImage: "checkmark.circle") { model.isSelecting = true }
                    Button("Copy Folder Path", systemImage: "doc.on.doc") { copyPath(model.currentPath) }
                    Button("Copy Folder for Bot", systemImage: "bubble.left.and.text.bubble.right") { copyBotPath(model.currentPath) }
                    Button("Open Terminal Here", systemImage: "terminal") { openTerminal(at: model.currentPath) }
                    Button("Home", systemImage: "house") { taskBag.run { await model.navigate(to: HomeAnchor.path) } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 10) {
            Button { taskBag.run { await model.navigateUp() } } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 34, height: 34)
            }
            .disabled(!model.canNavigateUp || model.isLoading)
            .buttonStyle(.plain)
            .modifier(GlassCapsuleModifier(interactive: model.canNavigateUp && !model.isLoading))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.breadcrumbs) { crumb in
                        Button {
                            taskBag.run { await model.navigate(to: crumb.path) }
                        } label: {
                            Text(crumb.title)
                                .litterMonoFont(size: 13, weight: crumb.isCurrent ? .semibold : .regular)
                                .foregroundStyle(crumb.isCurrent ? LitterTheme.textPrimary : LitterTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        if !crumb.isCurrent {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(LitterTheme.textMuted)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Button {
                model.showHidden.toggle()
            } label: {
                Image(systemName: model.showHidden ? "eye" : "eye.slash")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .modifier(GlassCapsuleModifier(interactive: true))
            .accessibilityLabel(model.showHidden ? "Hide hidden files" : "Show hidden files")

            Text(model.folderSummary)
                .litterMonoFont(size: 11, weight: .medium)
                .foregroundStyle(model.showHidden ? LitterTheme.accent : LitterTheme.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        fileContent
    }

    @ViewBuilder
    private var fileContent: some View {
        if model.isLoading {
            ProgressView("Loading files...")
                .foregroundStyle(LitterTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            LocalFileEmptyState(
                systemImage: "exclamationmark.triangle.fill",
                title: "Couldn't Load Folder",
                message: error,
                actionTitle: "Retry",
                action: { taskBag.run { await model.reload() } }
            )
        } else if model.entries.isEmpty {
            LocalFileEmptyState(
                systemImage: "folder",
                title: "This folder is empty",
                message: "Create a file, create a folder, or import a document from iOS Files.",
                actionTitle: "New File",
                action: { draftName = ""; showNewFile = true }
            )
        } else if model.visibleEntries.isEmpty {
            LocalFileEmptyState(
                systemImage: "magnifyingglass",
                title: "No Results",
                message: "No files match the current search and filter.",
                actionTitle: "Clear Search",
                action: { model.searchQuery = ""; model.activeFilter = .all }
            )
        } else {
            switch model.viewMode {
            case .list:
                listContent
            case .grid:
                gridContent
            }
        }
    }

    private var listContent: some View {
        List {
            if model.showsShortcuts {
                Section {
                    LocalFileWorkspaceOverview(
                        stats: model.workspaceStats,
                        currentPath: model.displayPath,
                        advancedLocationsEnabled: model.showAdvancedLocations,
                        onBuildStatus: { taskBag.run { await runBuildStatus() } },
                        onDoctor: { taskBag.run { await runFilesystemDoctor() } },
                        onTerminal: { openTerminal(at: model.currentPath) },
                        onCreateManifest: { taskBag.run { await createLitterBuildManifest() } }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
                    LocalFileFilterBar(selection: $model.activeFilter, counts: model.filterCounts)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 8, trailing: 14))
                    shortcutStrip
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
                }
            }
            Section {
                ForEach(model.visibleEntries) { entry in
                    entryButton(entry) {
                        LocalFileRow(
                            entry: entry,
                            isSelected: model.selectedPaths.contains(entry.path),
                            isFavorite: model.isFavorite(entry.path),
                            showsSelection: model.isSelecting,
                            onInspect: { inspectorTarget = entry }
                        )
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.58))
                }
            } header: {
                LocalFileSectionHeader(title: "Current Folder", detail: model.visibleSummary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.reload() }
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.showsShortcuts {
                    LocalFileWorkspaceOverview(
                        stats: model.workspaceStats,
                        currentPath: model.displayPath,
                        advancedLocationsEnabled: model.showAdvancedLocations,
                        onBuildStatus: { taskBag.run { await runBuildStatus() } },
                        onDoctor: { taskBag.run { await runFilesystemDoctor() } },
                        onTerminal: { openTerminal(at: model.currentPath) },
                        onCreateManifest: { taskBag.run { await createLitterBuildManifest() } }
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    LocalFileFilterBar(selection: $model.activeFilter, counts: model.filterCounts)
                        .padding(.horizontal, 14)
                    shortcutStrip
                        .padding(.horizontal, 14)
                }
                LocalFileSectionHeader(title: "Current Folder", detail: model.visibleSummary)
                    .padding(.horizontal, 18)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 12)], spacing: 12) {
                    ForEach(model.visibleEntries) { entry in
                        entryButton(entry) {
                            LocalFileGridItem(
                                entry: entry,
                                isSelected: model.selectedPaths.contains(entry.path),
                                isFavorite: model.isFavorite(entry.path),
                                showsSelection: model.isSelecting,
                                onInspect: { inspectorTarget = entry }
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
        }
        .refreshable { await model.reload() }
    }

    private var shortcutStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.quickLocations.isEmpty {
                shortcutRow(title: "Locations", shortcuts: model.quickLocations)
            }
            if !model.favoriteShortcuts.isEmpty {
                shortcutRow(title: "Favorites", shortcuts: model.favoriteShortcuts)
            }
            if !model.recentShortcuts.isEmpty {
                shortcutRow(title: "Recents", shortcuts: model.recentShortcuts)
            }
        }
    }

    private func shortcutRow(title: String, shortcuts: [LocalFileShortcut]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)
                .padding(.horizontal, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shortcuts) { shortcut in
                        Button {
                            taskBag.run { await model.navigate(to: shortcut.path) }
                        } label: {
                            LocalFileShortcutCard(shortcut: shortcut)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Copy Path", systemImage: "doc.on.doc") { copyPath(shortcut.path) }
                            Button("Copy Chat Link", systemImage: "link") { copyChatLink(title: shortcut.title, path: shortcut.path) }
                            Button("Copy for Bot", systemImage: "bubble.left.and.text.bubble.right") { copyBotPath(shortcut.path) }
                            Button("Open Terminal Here", systemImage: "terminal") { openTerminal(at: shortcut.path) }
                            if shortcut.canRemove {
                                Button("Remove", systemImage: "xmark.circle", role: .destructive) {
                                    model.removeShortcut(shortcut)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func entryButton<Content: View>(_ entry: LocalFileEntry, @ViewBuilder label: () -> Content) -> some View {
        Button {
            taskBag.run { await open(entry) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { deleteTarget = entry } label: { Label("Delete", systemImage: "trash") }
            Button { beginRename(entry) } label: { Label("Rename", systemImage: "pencil") }
                .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { model.toggleFavorite(entry) } label: {
                Label(model.isFavorite(entry.path) ? "Unfavorite" : "Favorite", systemImage: model.isFavorite(entry.path) ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .contextMenu { contextMenu(for: entry) }
    }

    @ViewBuilder
    private func contextMenu(for entry: LocalFileEntry) -> some View {
        Button("Preview", systemImage: "doc.text.magnifyingglass") { previewTarget = entry }
        Button("Inspector", systemImage: "info.circle") { inspectorTarget = entry }
        Button("Copy Path", systemImage: "doc.on.doc") { copyPath(entry.path) }
        Button("Copy Chat Link", systemImage: "link") { copyChatLink(title: entry.name, path: entry.path) }
        Button("Copy for Bot", systemImage: "bubble.left.and.text.bubble.right") { copyBotMention(entry) }
        if let linkTarget = entry.linkTarget {
            Button("Copy Link Target", systemImage: "link") { copyPath(linkTarget) }
        }
        Button(model.isFavorite(entry.path) ? "Remove Favorite" : "Add Favorite", systemImage: model.isFavorite(entry.path) ? "star.slash" : "star") {
            model.toggleFavorite(entry)
        }
        Button("Share", systemImage: "square.and.arrow.up") { taskBag.run { await share([entry]) } }
        if entry.kind == .file || entry.kind == .symlink {
            Button("Make Executable", systemImage: "checkmark.shield") { taskBag.run { await makeExecutable(entry) } }
        }
        Divider()
        if entry.isArchive {
            Button("Extract Here", systemImage: "archivebox") { taskBag.run { await extractArchive(entry) } }
        }
        Button("Compress", systemImage: "doc.zipper") { taskBag.run { await compress(entry) } }
        Button("Duplicate", systemImage: "plus.square.on.square") { taskBag.run { await duplicate(entry) } }
        Button("Move", systemImage: "folder") { beginMove(entry) }
        Button("Rename", systemImage: "pencil") { beginRename(entry) }
        Button("Open Terminal Here", systemImage: "terminal") { openTerminal(at: terminalPath(for: entry)) }
        Divider()
        if entry.kind == .directory {
            Button("Summarize Directory", systemImage: "text.badge.magnifyingglass") { taskBag.run { await summarizeDirectory(entry) } }
        }
        if entry.isSwiftSource {
            Button("Swift Check", systemImage: "checkmark.seal") { taskBag.run { await runSwiftCheck(entry) } }
        }
        if entry.name == "LitterBuild.json" {
            Button("Swift Build", systemImage: "hammer") { taskBag.run { await runSwiftBuild(projectPath: entry.path) } }
            Button("Build IPA", systemImage: "shippingbox") { taskBag.run { await runIPABuild(projectPath: entry.path) } }
        }
        if entry.isShellScript {
            Button("Run Script", systemImage: "terminal") { taskBag.run { await runShellScript(entry) } }
        }
        if entry.isBuildLog {
            Button("Explain Build Log", systemImage: "exclamationmark.bubble") { copyBuildLogPrompt(entry) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = entry }
    }

    private func open(_ entry: LocalFileEntry) async {
        if model.isSelecting {
            model.toggleSelection(entry)
            return
        }
        model.recordRecent(entry)
        if entry.isBrokenLink {
            alertMessage = "This symlink target is missing."
            return
        }
        if entry.kind == .directory {
            await model.open(entry)
            return
        }
        previewTarget = entry
    }

    private func beginRename(_ entry: LocalFileEntry) {
        renameTarget = entry
        renameText = entry.name
    }

    private func beginMove(_ entry: LocalFileEntry) {
        moveTarget = entry
        moveDestination = model.displayPath
    }

    private func copyPath(_ path: String) {
        UIPasteboard.general.string = path
        alertMessage = "Copied path."
    }

    private func copyBotPath(_ path: String) {
        UIPasteboard.general.string = "Use the file browser path \(path) as context."
        alertMessage = "Copied bot context."
    }

    private func copyChatLink(title: String, path: String) {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        UIPasteboard.general.string = "[\(escapedTitle)](\(chatFileLink(for: path)))"
        alertMessage = "Copied chat file link."
    }

    private func chatFileLink(for path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "#%[]()")
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return "litter-file://\(encodedPath)"
    }

    private func copyBotMention(_ entry: LocalFileEntry) {
        UIPasteboard.general.string = "Use \(entry.path) as context. Kind: \(entry.kindLabel)."
        alertMessage = "Copied bot context."
    }

    private func copyBuildLogPrompt(_ entry: LocalFileEntry) {
        UIPasteboard.general.string = "Read and explain this build log, then identify the first actionable failure: \(entry.path)"
        alertMessage = "Copied build log prompt."
    }

    private func openTerminal(at path: String) {
        terminalInitialDirectory = path
        settingsRequestedRoute = "terminal"
        appState.showSettings = true
        alertMessage = "Opening Settings Terminal."
    }

    private func terminalPath(for entry: LocalFileEntry) -> String {
        entry.kind == .directory ? entry.path : RemotePath.parse(path: entry.path).parent().asString()
    }

    private func copySelectedPaths() {
        let paths = model.selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        UIPasteboard.general.string = paths.joined(separator: "\n")
        alertMessage = "Copied \(paths.count) path(s)."
    }

    private func share(_ entries: [LocalFileEntry]) async {
        guard !entries.isEmpty else { return }
        do {
            let urls = try await model.export(entries: entries)
            sharePayload = LocalFileSharePayload(urls: urls)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func extractArchive(_ entry: LocalFileEntry) async {
        let nsName = entry.name as NSString
        let folderName = nsName.deletingPathExtension.isEmpty ? "\(entry.name) extracted" : "\(nsName.deletingPathExtension) extracted"
        let destination = RemotePath.parse(path: model.currentPath).join(name: folderName).asString()
        let result = await IshFS.extractArchive(path: entry.path, destination: destination)
        if result.exitCode == 0 {
            await model.reload()
            alertMessage = "Extracted to \(PathDisplay.display(destination, isLocal: true))."
        } else {
            alertMessage = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func compress(_ entry: LocalFileEntry) async {
        do {
            let destination = try await model.compress(entry)
            alertMessage = "Created \(PathDisplay.display(destination, isLocal: true))."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func duplicate(_ entry: LocalFileEntry) async {
        do {
            try await model.duplicate(entry)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func makeExecutable(_ entry: LocalFileEntry) async {
        do {
            try await IshFS.makeExecutable(path: entry.path)
            alertMessage = "Made \(entry.name) executable."
            await model.reload()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func runSwiftCheck(_ entry: LocalFileEntry) async {
        let result = await IshFS.run("litter-swift-check \(IshFS.shellQuote(entry.path))", cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Swift Check", command: "litter-swift-check \(entry.name)", result: result)
    }

    private func runSwiftBuild(projectPath: String? = nil) async {
        let path = projectPath ?? model.litterBuildManifestPath
        guard let path else {
            alertMessage = "No LitterBuild.json found in this folder."
            return
        }
        let result = await IshFS.run("litter-swift-build --timeout 600 \(IshFS.shellQuote(path))", cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Swift Build", command: "litter-swift-build \((path as NSString).lastPathComponent)", result: result)
    }

    private func runIPABuild(projectPath: String? = nil) async {
        let path = projectPath ?? model.litterBuildManifestPath
        guard let path else {
            alertMessage = "No LitterBuild.json found in this folder."
            return
        }
        let result = await IshFS.run("litter-ipa-build --timeout 900 \(IshFS.shellQuote(path))", cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "IPA Build", command: "litter-ipa-build \((path as NSString).lastPathComponent)", result: result)
        await model.reload()
    }

    private func runRecursiveSearch() async {
        let query = model.trimmedSearchQuery
        guard !query.isEmpty else { return }
        let includeHidden = model.showHidden ? "1" : "0"
        let command = """
        q=\(IshFS.shellQuote(query))
        dir=\(IshFS.shellQuote(model.currentPath))
        include_hidden=\(includeHidden)
        if command -v rg >/dev/null 2>&1; then
          if [ "$include_hidden" -eq 1 ]; then
            rg -n --hidden --glob '!/.git/*' -- "$q" "$dir"
          else
            rg -n --glob '!.*' -- "$q" "$dir"
          fi
        else
          if [ "$include_hidden" -eq 1 ]; then
            find "$dir" -type f -print 2>/dev/null
          else
            find "$dir" -path '*/.*' -prune -o -type f -print 2>/dev/null
          fi | head -n 500 | while IFS= read -r f; do
            grep -n -I -- "$q" "$f" 2>/dev/null | sed "s#^#$f:#"
          done
        fi
        """
        let result = await IshFS.run(command, cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Recursive Search", command: "search \(query)", result: result)
    }

    private func runLargeFileSearch() async {
        let command = """
        dir=\(IshFS.shellQuote(model.currentPath))
        find "$dir" -type f 2>/dev/null | head -n 1200 | while IFS= read -r f; do
          size=$(wc -c < "$f" 2>/dev/null || echo 0)
          if [ "$size" -ge 1048576 ]; then printf '%12s  %s\n' "$size" "$f"; fi
        done | sort -nr | head -n 100
        """
        let result = await IshFS.run(command, cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Large Files", command: "find files over 1 MB", result: result)
    }

    private func runTreeSnapshot() async {
        let command = """
        dir=\(IshFS.shellQuote(model.currentPath))
        find "$dir" -maxdepth 3 2>/dev/null | sed "s#^$dir#.#" | head -n 300
        """
        let result = await IshFS.run(command, cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Folder Tree", command: "tree \(model.displayPath)", result: result)
    }

    private func runGitStatus() async {
        let command = """
        dir=\(IshFS.shellQuote(model.currentPath))
        top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
        if [ -z "$top" ]; then echo "No git repository found from $dir"; exit 1; fi
        git -C "$top" status --short --branch
        """
        let result = await IshFS.run(command, cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Git Status", command: "git status", result: result)
    }

    private func runBuildStatus() async {
        let result = await IshFS.run("litter-build-status", cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Build Status", command: "litter-build-status", result: result)
    }

    private func runFilesystemDoctor() async {
        let result = await IshFS.run("litter-fs-doctor", cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Filesystem Doctor", command: "litter-fs-doctor", result: result)
    }

    private func createLitterBuildManifest() async {
        let target = RemotePath.parse(path: model.currentPath).join(name: "LitterBuild.json").asString()
        guard !(await IshFS.exists(path: target)) else {
            alertMessage = "LitterBuild.json already exists here."
            return
        }
        let folderName = (model.currentPath as NSString).lastPathComponent
        let appName = folderName.isEmpty ? "LitterApp" : folderName
        let manifest = """
        {
          "name": "\(appName)",
          "entrypoint": "main.swift",
          "sources": ["main.swift"],
          "resources": []
        }
        """
        do {
            try await IshFS.writeTextFile(path: target, text: manifest + "\n")
            let mainPath = RemotePath.parse(path: model.currentPath).join(name: "main.swift").asString()
            if !(await IshFS.exists(path: mainPath)) {
                try await IshFS.writeTextFile(path: mainPath, text: "import Foundation\n\nprint(\"Hello from Litter\")\n")
            }
            await model.reload()
            alertMessage = "Created LitterBuild.json."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func summarizeDirectory(_ entry: LocalFileEntry) async {
        let command = """
        dir=\(IshFS.shellQuote(entry.path))
        echo "Path: $dir"
        echo
        echo "Counts:"
        find "$dir" -maxdepth 1 -type d 2>/dev/null | wc -l | sed 's/^/folders: /'
        find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | sed 's/^/files: /'
        echo
        echo "Top files:"
        find "$dir" -maxdepth 2 -type f 2>/dev/null | head -n 80
        """
        let result = await IshFS.run(command, cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Directory Summary", command: "summarize \(entry.name)", result: result)
    }

    private func runShellScript(_ entry: LocalFileEntry) async {
        let result = await IshFS.run("sh \(IshFS.shellQuote(entry.path))", cwd: model.currentPath)
        commandOutput = LocalCommandOutput(title: "Script Output", command: "sh \(entry.name)", result: result)
    }

    private func create(kind: LocalFileEntry.Kind) async {
        let validation = validateName(draftName)
        draftName = ""
        guard case .valid(let name) = validation else {
            alertMessage = validation.errorMessage
            return
        }
        do {
            try await model.create(name: name, kind: kind)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func renameSelected() async {
        guard let target = renameTarget else { return }
        let validation = validateName(renameText)
        renameTarget = nil
        guard case .valid(let name) = validation else {
            alertMessage = validation.errorMessage
            return
        }
        guard name != target.name else { return }
        do {
            try await model.rename(target, to: name)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func moveSelected() async {
        guard let target = moveTarget else { return }
        let destination = PathDisplay.expand(moveDestination.trimmingCharacters(in: .whitespacesAndNewlines), isLocal: true)
        moveTarget = nil
        guard !destination.isEmpty else {
            alertMessage = "Destination folder cannot be empty."
            return
        }
        do {
            try await model.move(target, toDirectory: destination)
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

    private func deleteSelection() async {
        do {
            try await model.deleteSelectedEntries()
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

    private enum NameValidation {
        case valid(String)
        case invalid(String)

        var errorMessage: String? {
            guard case .invalid(let message) = self else { return nil }
            return message
        }
    }

    private func validateName(_ raw: String) -> NameValidation {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .invalid("Name cannot be empty.") }
        guard name != ".", name != ".." else { return .invalid("That name is reserved by the filesystem.") }
        guard !name.contains("/"), !name.contains("\\") else {
            return .invalid("Use a single file or folder name, not a path.")
        }
        return .valid(name)
    }
}


private enum LocalFileFilter: String, CaseIterable, Identifiable {
    case all
    case folders
    case code
    case images
    case archives
    case builds
    case recent
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .folders: return "Folders"
        case .code: return "Code"
        case .images: return "Images"
        case .archives: return "Archives"
        case .builds: return "Builds"
        case .recent: return "Recent"
        case .large: return "Large"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .folders: return "folder"
        case .code: return "curlybraces"
        case .images: return "photo"
        case .archives: return "archivebox"
        case .builds: return "shippingbox"
        case .recent: return "clock"
        case .large: return "internaldrive"
        }
    }

    func matches(_ entry: LocalFileEntry) -> Bool {
        switch self {
        case .all: return true
        case .folders: return entry.kind == .directory
        case .code: return entry.isCode
        case .images: return entry.isImage
        case .archives: return entry.isArchive
        case .builds: return entry.isBuildArtifact || entry.name == "LitterBuild.json"
        case .recent: return entry.isRecentlyModified
        case .large: return entry.isLarge
        }
    }
}

private struct LocalFileWorkspaceStats: Equatable {
    let folders: Int
    let files: Int
    let code: Int
    let builds: Int
    let images: Int
    let totalBytes: Int64

    var totalItems: Int { folders + files }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

private enum LocalFileViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

private enum LocalFileSort: String, CaseIterable, Identifiable {
    case name
    case date
    case size
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date Modified"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .date: return "calendar"
        case .size: return "arrow.up.arrow.down"
        case .kind: return "doc.on.doc"
        }
    }
}

private struct LocalPathBreadcrumb: Identifiable {
    let id: String
    let title: String
    let path: String
    let isCurrent: Bool
}

private struct LocalFileShortcut: Identifiable, Hashable {
    enum Source: String {
        case quick
        case favorite
        case recent
    }

    let source: Source
    let path: String
    let title: String
    let subtitle: String
    let systemImage: String
    let kind: LocalFileEntry.Kind

    var id: String { "\(source.rawValue):\(path)" }
    var canRemove: Bool { source != .quick }
}

private struct LocalFileStoredShortcut: Codable, Hashable {
    let path: String
    let name: String
    let kindRaw: String
    let date: Date

    var kind: LocalFileEntry.Kind {
        LocalFileEntry.Kind(rawValue: kindRaw) ?? .directory
    }
}

@MainActor
@Observable
private final class LocalFileWorkspaceModel {
    var currentPath = HomeAnchor.path
    var entries: [LocalFileEntry] = []
    var isLoading = false
    var errorMessage: String?
    var showHidden = UserDefaults.standard.object(forKey: LocalFileWorkspaceModel.showHiddenKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHidden, forKey: Self.showHiddenKey) }
    }
    var showAdvancedLocations = UserDefaults.standard.object(forKey: LocalFileWorkspaceModel.showAdvancedLocationsKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showAdvancedLocations, forKey: Self.showAdvancedLocationsKey) }
    }
    var openFile: LocalFileEntry?
    var searchQuery = ""
    var sort: LocalFileSort = .name
    var viewMode: LocalFileViewMode = .list
    var activeFilter: LocalFileFilter = .all
    var isSelecting = false
    var selectedPaths: Set<String> = []

    private var favoriteItems: [LocalFileStoredShortcut] = []
    private var recentItems: [LocalFileStoredShortcut] = []

    private static let showHiddenKey = "local_file_workspace_show_hidden_v1"
    private static let showAdvancedLocationsKey = "local_file_workspace_show_advanced_locations_v1"
    private let favoritesKey = "local_file_workspace_favorites_v1"
    private let recentsKey = "local_file_workspace_recents_v1"
    private let maxStoredShortcuts = 20

    var displayPath: String {
        PathDisplay.display(currentPath, isLocal: true)
    }

    var canNavigateUp: Bool {
        !currentPath.isEmpty && currentPath != "/" && currentPath != HomeAnchor.path
    }

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var visibleEntries: [LocalFileEntry] {
        let searched: [LocalFileEntry]
        if trimmedSearchQuery.isEmpty {
            searched = entries
        } else {
            searched = entries.filter { entry in
                entry.name.localizedCaseInsensitiveContains(trimmedSearchQuery) ||
                    entry.path.localizedCaseInsensitiveContains(trimmedSearchQuery) ||
                    entry.kindLabel.localizedCaseInsensitiveContains(trimmedSearchQuery)
            }
        }
        return sortEntries(searched.filter { activeFilter.matches($0) })
    }

    var filterCounts: [LocalFileFilter: Int] {
        Dictionary(uniqueKeysWithValues: LocalFileFilter.allCases.map { filter in
            (filter, entries.filter { filter.matches($0) }.count)
        })
    }

    var workspaceStats: LocalFileWorkspaceStats {
        LocalFileWorkspaceStats(
            folders: entries.filter { $0.kind == .directory }.count,
            files: entries.filter { $0.kind != .directory }.count,
            code: entries.filter(\.isCode).count,
            builds: entries.filter { $0.isBuildArtifact || $0.name == "LitterBuild.json" }.count,
            images: entries.filter(\.isImage).count,
            totalBytes: entries.reduce(Int64(0)) { $0 + max($1.size, 0) }
        )
    }

    var selectedEntries: [LocalFileEntry] {
        entries.filter { selectedPaths.contains($0.path) }
    }

    var litterBuildManifestPath: String? {
        entries.first { $0.name == "LitterBuild.json" && $0.kind != .directory }?.path
    }

    var hasLitterBuildManifest: Bool {
        litterBuildManifestPath != nil
    }

    var showsShortcuts: Bool {
        trimmedSearchQuery.isEmpty && !isSelecting
    }

    var visibleSummary: String {
        "\(visibleEntries.count) of \(entries.count) items"
    }

    var folderSummary: String {
        let folderCount = entries.filter { $0.kind == .directory }.count
        let fileCount = entries.count - folderCount
        let hiddenNote = showHidden ? " incl. hidden" : ""
        return "\(folderCount) folders, \(fileCount) files\(hiddenNote)"
    }

    var quickLocations: [LocalFileShortcut] {
        var locations = [
            LocalFileShortcut(source: .quick, path: HomeAnchor.path, title: "Home", subtitle: "~", systemImage: "house.fill", kind: .directory),
            LocalFileShortcut(source: .quick, path: "/root/litter", title: "Litter", subtitle: "/root/litter", systemImage: "shippingbox.fill", kind: .directory),
            LocalFileShortcut(source: .quick, path: "/root/projects", title: "Projects", subtitle: "/root/projects", systemImage: "folder.fill.badge.gearshape", kind: .directory),
            LocalFileShortcut(source: .quick, path: "/root/.litter/builds", title: "Builds", subtitle: "~/.litter/builds", systemImage: "hammer.fill", kind: .directory),
            LocalFileShortcut(source: .quick, path: "/mnt/apps", title: "App Files", subtitle: "/mnt/apps", systemImage: "externaldrive.fill", kind: .directory),
            LocalFileShortcut(source: .quick, path: "/mnt/codex", title: "Codex Home", subtitle: "/mnt/codex", systemImage: "folder.badge.gearshape", kind: .directory)
        ]
        if showAdvancedLocations {
            locations += [
                LocalFileShortcut(source: .quick, path: "/", title: "iSH Root", subtitle: "/", systemImage: "server.rack", kind: .directory),
                LocalFileShortcut(source: .quick, path: "/tmp", title: "Temp", subtitle: "/tmp", systemImage: "tray.fill", kind: .directory),
                LocalFileShortcut(source: .quick, path: "/usr/local/bin", title: "Commands", subtitle: "/usr/local/bin", systemImage: "terminal.fill", kind: .directory),
                LocalFileShortcut(source: .quick, path: "/etc", title: "Config", subtitle: "/etc", systemImage: "gearshape.fill", kind: .directory)
            ]
        }
        return locations
    }

    var favoriteShortcuts: [LocalFileShortcut] {
        favoriteItems.prefix(10).map { shortcut($0, source: .favorite) }
    }

    var recentShortcuts: [LocalFileShortcut] {
        recentItems.prefix(10).map { shortcut($0, source: .recent) }
    }

    var breadcrumbs: [LocalPathBreadcrumb] {
        let display = displayPath
        if display == "~" {
            return [LocalPathBreadcrumb(id: HomeAnchor.path, title: "~", path: HomeAnchor.path, isCurrent: true)]
        }
        if display.hasPrefix("~/") {
            let parts = display.dropFirst(2).split(separator: "/").map(String.init)
            var crumbs = [LocalPathBreadcrumb(id: HomeAnchor.path, title: "~", path: HomeAnchor.path, isCurrent: parts.isEmpty)]
            var path = HomeAnchor.path
            for (index, part) in parts.enumerated() {
                path = RemotePath.parse(path: path).join(name: part).asString()
                crumbs.append(LocalPathBreadcrumb(id: path, title: part, path: path, isCurrent: index == parts.count - 1))
            }
            return crumbs
        }
        let parsed = RemotePath.parse(path: currentPath).segments()
        guard !parsed.isEmpty else {
            return [LocalPathBreadcrumb(id: "/", title: "/", path: "/", isCurrent: true)]
        }
        return parsed.enumerated().map { index, segment in
            LocalPathBreadcrumb(id: segment.fullPath, title: segment.label, path: segment.fullPath, isCurrent: index == parsed.count - 1)
        }
    }

    func loadInitial(path: String? = nil) async {
        loadStoredShortcuts()
        let target = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        await reload(path: target?.isEmpty == false ? target! : currentPath)
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
            selectedPaths = selectedPaths.intersection(Set(entries.map(\.path)))
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func open(_ entry: LocalFileEntry) async {
        switch entry.kind {
        case .directory:
            recordRecent(entry)
            await reload(path: entry.path)
        case .file, .symlink, .special:
            recordRecent(entry)
            openFile = entry
        }
    }

    func navigate(to path: String) async {
        let expanded = PathDisplay.expand(path, isLocal: true)
        await reload(path: expanded)
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
        case .file, .symlink, .special:
            try await IshFS.createEmptyFile(path: target)
        }
        await reload()
    }

    func rename(_ entry: LocalFileEntry, to name: String) async throws {
        let target = RemotePath.parse(path: currentPath).join(name: name).asString()
        try await IshFS.rename(path: entry.path, to: target)
        removeStoredPath(entry.path)
        await reload()
    }

    func move(_ entry: LocalFileEntry, toDirectory directory: String) async throws {
        let target = RemotePath.parse(path: directory).join(name: entry.name).asString()
        try await IshFS.rename(path: entry.path, to: target)
        removeStoredPath(entry.path)
        await reload()
    }

    func duplicate(_ entry: LocalFileEntry) async throws {
        let name = try await availableDuplicateName(for: entry.name)
        let target = RemotePath.parse(path: currentPath).join(name: name).asString()
        try await IshFS.duplicate(path: entry.path, destination: target)
        await reload()
    }

    @discardableResult
    func compress(_ entry: LocalFileEntry) async throws -> String {
        let name = try await availableArchiveName(for: entry.name)
        let target = RemotePath.parse(path: currentPath).join(name: name).asString()
        let result = await IshFS.compress(path: entry.path, destination: target)
        guard result.exitCode == 0 else { throw makeError("Could not compress \(entry.name)", result: result) }
        await reload()
        return target
    }

    func delete(_ entry: LocalFileEntry) async throws {
        try await IshFS.delete(path: entry.path)
        removeStoredPath(entry.path)
        selectedPaths.remove(entry.path)
        await reload()
    }

    func deleteSelectedEntries() async throws {
        let targets = selectedEntries
        for entry in targets {
            try await IshFS.delete(path: entry.path)
            removeStoredPath(entry.path)
        }
        clearSelection()
        await reload()
    }

    func export(entries: [LocalFileEntry]) async throws -> [URL] {
        var urls: [URL] = []
        for entry in entries {
            if entry.kind == .directory {
                let archivePath = "/tmp/litter-share-\(UUID().uuidString).tar.gz"
                let result = await IshFS.compress(path: entry.path, destination: archivePath)
                guard result.exitCode == 0 else { throw makeError("Could not prepare \(entry.name) for sharing", result: result) }
                urls.append(try await IshFS.copyFileToTemporaryURL(path: archivePath, suggestedFileName: "\(entry.name).tar.gz"))
                _ = await IshFS.run("rm -f \(IshFS.shellQuote(archivePath))")
            } else {
                urls.append(try await IshFS.copyFileToTemporaryURL(path: entry.path, suggestedFileName: entry.name))
            }
        }
        return urls
    }

    func importFile(from url: URL) async throws {
        _ = try await ConversationAttachmentSupport.importURLToFakeFS(
            url: url,
            destinationDirectory: currentPath,
            treatImagesAsFiles: true
        )
        await reload()
    }

    func isFavorite(_ path: String) -> Bool {
        favoriteItems.contains { $0.path == path }
    }

    func toggleFavorite(_ entry: LocalFileEntry) {
        if let index = favoriteItems.firstIndex(where: { $0.path == entry.path }) {
            favoriteItems.remove(at: index)
        } else {
            favoriteItems.insert(storedShortcut(entry), at: 0)
            favoriteItems = Array(favoriteItems.prefix(maxStoredShortcuts))
        }
        save(favoriteItems, key: favoritesKey)
    }

    func removeShortcut(_ shortcut: LocalFileShortcut) {
        switch shortcut.source {
        case .quick:
            return
        case .favorite:
            favoriteItems.removeAll { $0.path == shortcut.path }
            save(favoriteItems, key: favoritesKey)
        case .recent:
            recentItems.removeAll { $0.path == shortcut.path }
            save(recentItems, key: recentsKey)
        }
    }

    func recordRecent(_ entry: LocalFileEntry) {
        let stored = storedShortcut(entry)
        recentItems.removeAll { $0.path == entry.path }
        recentItems.insert(stored, at: 0)
        recentItems = Array(recentItems.prefix(maxStoredShortcuts))
        save(recentItems, key: recentsKey)
    }

    func toggleSelection(_ entry: LocalFileEntry) {
        if selectedPaths.contains(entry.path) {
            selectedPaths.remove(entry.path)
        } else {
            selectedPaths.insert(entry.path)
        }
    }

    func clearSelection() {
        selectedPaths.removeAll()
        isSelecting = false
    }

    private func sortEntries(_ entries: [LocalFileEntry]) -> [LocalFileEntry] {
        entries.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .directory }
            switch sort {
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .date:
                return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            case .size:
                return lhs.size > rhs.size
            case .kind:
                let kindCompare = lhs.kindLabel.localizedStandardCompare(rhs.kindLabel)
                if kindCompare != .orderedSame { return kindCompare == .orderedAscending }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func loadStoredShortcuts() {
        favoriteItems = load(key: favoritesKey)
        recentItems = load(key: recentsKey)
    }

    private func shortcut(_ stored: LocalFileStoredShortcut, source: LocalFileShortcut.Source) -> LocalFileShortcut {
        let display = PathDisplay.display(stored.path, isLocal: true)
        return LocalFileShortcut(
            source: source,
            path: stored.path,
            title: stored.name,
            subtitle: display,
            systemImage: LocalFileEntry.iconName(for: stored.name, kind: stored.kind),
            kind: stored.kind
        )
    }

    private func storedShortcut(_ entry: LocalFileEntry) -> LocalFileStoredShortcut {
        LocalFileStoredShortcut(path: entry.path, name: entry.name, kindRaw: entry.kind.rawValue, date: Date())
    }

    private func load(key: String) -> [LocalFileStoredShortcut] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LocalFileStoredShortcut].self, from: data) else { return [] }
        return decoded.filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func save(_ items: [LocalFileStoredShortcut], key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func removeStoredPath(_ path: String) {
        favoriteItems.removeAll { $0.path == path }
        recentItems.removeAll { $0.path == path }
        save(favoriteItems, key: favoritesKey)
        save(recentItems, key: recentsKey)
    }

    private func availableDuplicateName(for name: String) async throws -> String {
        let nsName = name as NSString
        let stem = nsName.deletingPathExtension.isEmpty ? name : nsName.deletingPathExtension
        let ext = nsName.pathExtension
        let candidates: [String] = (0..<100).map { index in
            let suffix = index == 0 ? " copy" : " copy \(index + 1)"
            return ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
        }
        return try await firstAvailableName(candidates: candidates)
    }

    private func availableArchiveName(for name: String) async throws -> String {
        let base = "\(name).tar.gz"
        let candidates: [String] = (0..<100).map { index in
            index == 0 ? base : "\(name) \(index + 1).tar.gz"
        }
        return try await firstAvailableName(candidates: candidates)
    }

    private func firstAvailableName(candidates: [String]) async throws -> String {
        for candidate in candidates {
            let target = RemotePath.parse(path: currentPath).join(name: candidate).asString()
            if !(await IshFS.exists(path: target)) {
                return candidate
            }
        }
        throw NSError(domain: "LocalFileWorkspace", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not find a free filename."])
    }

    private func makeError(_ fallback: String, result: IshFS.Result) -> NSError {
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSError(
            domain: "LocalFileWorkspace",
            code: Int(result.exitCode),
            userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? fallback : output]
        )
    }
}

struct LocalFileEntry: Identifiable, Hashable {
    enum Kind: String, Hashable, Codable {
        case file
        case directory
        case symlink
        case special
    }

    let kind: Kind
    let name: String
    let path: String
    let size: Int64
    let modifiedAt: Date?
    let permissions: String
    let linkTarget: String?
    let isBrokenLink: Bool

    var id: String { path }

    var detailText: String {
        var parts: [String] = [kindLabel]
        if kind == .file || kind == .symlink {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let linkTarget {
            parts.append("-> \(linkTarget)")
        }
        if let modifiedAt = modifiedAt {
            parts.append(DateFormatter.localizedString(from: modifiedAt, dateStyle: .medium, timeStyle: .short))
        }
        if !permissions.isEmpty {
            parts.append(permissions)
        }
        return parts.joined(separator: " - ")
    }

    var kindLabel: String {
        switch kind {
        case .directory:
            return "Folder"
        case .symlink:
            return isBrokenLink ? "Broken Link" : "Symlink"
        case .special:
            return "Special File"
        case .file:
            let ext = (name as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "Document" : "\(ext) File"
        }
    }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "bmp", "svg"].contains(fileExtension)
    }

    var isArchive: Bool {
        ConversationAttachmentSupport.isArchiveName(name)
    }

    var isSwiftSource: Bool { fileExtension == "swift" }

    var isShellScript: Bool { fileExtension == "sh" }

    var isBuildLog: Bool { fileExtension == "log" || name.localizedCaseInsensitiveContains("build") || path.contains("/builds/") }

    var isBuildArtifact: Bool {
        ["ipa", "app", "dSYM", "xcarchive"].contains { $0.caseInsensitiveCompare(fileExtension) == .orderedSame || name.hasSuffix($0) }
    }

    var isCode: Bool {
        ["swift", "rs", "js", "ts", "tsx", "jsx", "py", "sh", "rb", "go", "c", "h", "m", "mm", "cpp", "json", "yml", "yaml", "toml", "xml", "html", "css", "md"].contains(fileExtension)
    }

    var isLarge: Bool { size >= 1_048_576 }

    var isRecentlyModified: Bool {
        guard let modifiedAt else { return false }
        return modifiedAt > Date().addingTimeInterval(-86_400)
    }

    var badgeText: String? {
        if isBrokenLink { return "Broken" }
        if isSwiftSource { return "Swift" }
        if isBuildArtifact { return "Artifact" }
        if isBuildLog { return "Log" }
        if isArchive { return "Archive" }
        if isImage { return "Image" }
        if isLarge { return "Large" }
        if kind == .directory && name == ".git" { return "Git" }
        return nil
    }

    var compactMetaText: String {
        if kind == .directory { return "Folder" }
        let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        guard let modifiedAt else { return "\(kindLabel) - \(sizeText)" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let dateText = formatter.localizedString(for: modifiedAt, relativeTo: Date())
        return "\(kindLabel) - \(sizeText) - \(dateText)"
    }

    var isTextPreviewable: Bool {
        if kind == .directory || kind == .special || isImage || isArchive { return false }
        return [
            "", "txt", "md", "swift", "rs", "js", "ts", "tsx", "jsx", "py", "sh", "rb", "go", "c", "h", "m", "mm", "cpp", "json", "yml", "yaml", "toml", "xml", "html", "css", "log", "env"
        ].contains(fileExtension)
    }

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var iconName: String {
        Self.iconName(for: name, kind: kind)
    }

    static func iconName(for name: String, kind: Kind = .file) -> String {
        switch kind {
        case .directory: return "folder.fill"
        case .symlink: return "link"
        case .special: return "gearshape"
        case .file: break
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "rs", "js", "ts", "tsx", "jsx", "py", "sh", "rb", "go", "c", "h", "m", "mm", "cpp", "json", "yml", "yaml", "toml", "md":
            return "curlybraces"
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "bmp", "svg":
            return "photo"
        case "zip", "rar", "7z", "gz", "tar", "xz", "tgz", "txz":
            return "archivebox"
        case "ipa", "app":
            return "shippingbox"
        default:
            return "doc.text"
        }
    }
}

private struct LocalFileWorkspaceOverview: View {
    let stats: LocalFileWorkspaceStats
    let currentPath: String
    let advancedLocationsEnabled: Bool
    let onBuildStatus: () -> Void
    let onDoctor: () -> Void
    let onTerminal: () -> Void
    let onCreateManifest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace")
                        .litterFont(.headline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text(currentPath)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Label(advancedLocationsEnabled ? "Advanced" : "Clean", systemImage: advancedLocationsEnabled ? "lock.open" : "lock")
                    .litterMonoFont(size: 10, weight: .semibold)
                    .foregroundStyle(advancedLocationsEnabled ? LitterTheme.warning : LitterTheme.success)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    LocalFileStatPill(title: "Items", value: "\(stats.totalItems)", systemImage: "square.grid.2x2")
                    LocalFileStatPill(title: "Code", value: "\(stats.code)", systemImage: "curlybraces")
                    LocalFileStatPill(title: "Builds", value: "\(stats.builds)", systemImage: "hammer")
                    LocalFileStatPill(title: "Size", value: stats.sizeText, systemImage: "internaldrive")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    LocalFileActionChip(title: "Terminal", systemImage: "terminal", action: onTerminal)
                    LocalFileActionChip(title: "Builds", systemImage: "chart.bar.doc.horizontal", action: onBuildStatus)
                    LocalFileActionChip(title: "Doctor", systemImage: "stethoscope", action: onDoctor)
                    LocalFileActionChip(title: "Manifest", systemImage: "doc.badge.gearshape", action: onCreateManifest)
                }
            }
        }
        .padding(12)
        .background(LitterTheme.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LitterTheme.border.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct LocalFileStatPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LitterTheme.accent)
            Text(value)
                .litterMonoFont(size: 11, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .litterMonoFont(size: 9, weight: .regular)
                .foregroundStyle(LitterTheme.textMuted)
        }
        .frame(width: 72, alignment: .leading)
        .padding(8)
        .background(LitterTheme.surfaceLight.opacity(0.36), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LocalFileActionChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .litterMonoFont(size: 11, weight: .semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LitterTheme.textPrimary)
        .background(LitterTheme.surfaceLight.opacity(0.42), in: Capsule())
    }
}

private struct LocalFileFilterBar: View {
    @Binding var selection: LocalFileFilter
    let counts: [LocalFileFilter: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LocalFileFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.systemImage)
                            Text(filter.title)
                            Text("\(counts[filter] ?? 0)")
                                .foregroundStyle(selection == filter ? LitterTheme.textPrimary : LitterTheme.textMuted)
                        }
                        .litterMonoFont(size: 11, weight: .semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(selection == filter ? LitterTheme.accent.opacity(0.22) : LitterTheme.surface.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == filter ? LitterTheme.accent : LitterTheme.textSecondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct LocalFileSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)
            Spacer()
            Text(detail)
                .litterMonoFont(size: 11, weight: .medium)
                .foregroundStyle(LitterTheme.textMuted)
        }
    }
}

private struct LocalFileRow: View {
    let entry: LocalFileEntry
    let isSelected: Bool
    let isFavorite: Bool
    let showsSelection: Bool
    let onInspect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? LitterTheme.accent : LitterTheme.textMuted)
                    .frame(width: 24)
            }
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: entry.iconName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(entry.kind == .directory ? LitterTheme.accent : (entry.isBrokenLink ? LitterTheme.warning : LitterTheme.textSecondary))
                    .frame(width: 34, height: 34)
                if entry.isRecentlyModified {
                    Circle()
                        .fill(LitterTheme.success)
                        .frame(width: 7, height: 7)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .litterFont(.subheadline, weight: .medium)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.yellow)
                    }
                    if let badge = entry.badgeText {
                        LocalFileBadge(text: badge)
                    }
                }
                Text(entry.compactMetaText)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(LitterTheme.textMuted)
                    .lineLimit(1)
                if !entry.permissions.isEmpty {
                    Text(entry.permissions)
                        .litterMonoFont(size: 10, weight: .regular)
                        .foregroundStyle(LitterTheme.textMuted.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onInspect) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LitterTheme.textMuted)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            Image(systemName: entry.kind == .directory ? "chevron.right" : "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LitterTheme.textMuted)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct LocalFileGridItem: View {
    let entry: LocalFileEntry
    let isSelected: Bool
    let isFavorite: Bool
    let showsSelection: Bool
    let onInspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LitterTheme.surface.opacity(0.62))
                    .frame(height: 82)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(LitterTheme.border.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: entry.iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(entry.kind == .directory ? LitterTheme.accent : (entry.isBrokenLink ? LitterTheme.warning : LitterTheme.textSecondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 4) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.yellow)
                        }
                        if showsSelection {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(isSelected ? LitterTheme.accent : LitterTheme.textMuted)
                        }
                    }
                    if let badge = entry.badgeText {
                        LocalFileBadge(text: badge)
                    }
                }
                .padding(7)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .litterFont(.caption, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .topLeading)
                Text(entry.kind == .directory ? "Folder" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .litterMonoFont(size: 10, weight: .regular)
                    .foregroundStyle(LitterTheme.textMuted)
                    .lineLimit(1)
                Button(action: onInspect) {
                    Label("Info", systemImage: "info.circle")
                        .litterMonoFont(size: 10, weight: .medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LitterTheme.accent)
            }
        }
        .padding(8)
        .background(LitterTheme.surfaceLight.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LocalFileBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .litterMonoFont(size: 9, weight: .semibold)
            .foregroundStyle(LitterTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(LitterTheme.accent.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}

private struct LocalFileShortcutCard: View {
    let shortcut: LocalFileShortcut

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: shortcut.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(shortcut.source == .quick ? LitterTheme.accent : LitterTheme.textSecondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.title)
                    .litterFont(.caption, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .lineLimit(1)
                Text(shortcut.subtitle)
                    .litterMonoFont(size: 10, weight: .regular)
                    .foregroundStyle(LitterTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(width: 154, alignment: .leading)
        .padding(10)
        .background(LitterTheme.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LitterTheme.border.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct LocalFileEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(systemImage.contains("triangle") ? LitterTheme.warning : LitterTheme.textMuted)
            Text(title)
                .litterFont(.headline)
                .foregroundStyle(LitterTheme.textPrimary)
            Text(message)
                .litterFont(.footnote)
                .foregroundStyle(LitterTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .foregroundStyle(LitterTheme.accent)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @StateObject private var taskBag = ViewTaskBag()
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
                        taskBag.run { await save() }
                    } label: {
                        if isSaving { ProgressView().scaleEffect(0.8) } else { Text("Save") }
                    }
                    .disabled(isLoading || isSaving || !hasUnsavedChanges)
                    .foregroundStyle(LitterTheme.accent)
                }
            }
            .task { await load() }
            .onDisappear { taskBag.cancelAll() }
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

private struct LocalFilePreviewSheet: View {
    let file: LocalFileEntry
    let onEdit: () -> Void
    let onShare: () -> Void
    let onCopyPath: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var textPreview: String?
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                LitterTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewHero
                        LocalFileInfoPanel(file: file)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: onCopyPath) { Image(systemName: "doc.on.doc") }
                    Button(action: onShare) { Image(systemName: "square.and.arrow.up") }
                    if file.isTextPreviewable {
                        Button("Edit") { onEdit() }
                    }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var previewHero: some View {
        if isLoading {
            ProgressView("Preparing Preview...")
                .frame(maxWidth: .infinity, minHeight: 220)
                .foregroundStyle(LitterTheme.textSecondary)
        } else if let image = image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(LitterTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let textPreview = textPreview {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(textPreview.isEmpty ? " " : textPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(LitterTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(LitterTheme.codeBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            VStack(spacing: 12) {
                Image(systemName: file.iconName)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(file.kind == .directory ? LitterTheme.accent : LitterTheme.textSecondary)
                Text(errorMessage ?? "No inline preview is available for this file.")
                    .litterFont(.footnote)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(LitterTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if file.isImage {
                let data = try await IshFS.readFileData(path: file.path, maxBytes: 24_000_000)
                image = UIImage(data: data)
                if image == nil { errorMessage = "This image format could not be previewed." }
            } else if file.isTextPreviewable {
                textPreview = try await IshFS.readTextFile(path: file.path, maxBytes: 160_000)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LocalFileInfoPanel: View {
    let file: LocalFileEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow("Kind", file.kindLabel)
            infoRow("Path", file.path)
            if file.kind == .file || file.kind == .symlink {
                infoRow("Size", ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
            }
            if let modifiedAt = file.modifiedAt {
                infoRow("Modified", DateFormatter.localizedString(from: modifiedAt, dateStyle: .medium, timeStyle: .short))
            }
            if let linkTarget = file.linkTarget {
                infoRow(file.isBrokenLink ? "Broken Link Target" : "Link Target", linkTarget)
            }
            if !file.permissions.isEmpty {
                infoRow("Permissions", file.permissions)
            }
        }
        .padding(14)
        .background(LitterTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)
            Text(value)
                .litterMonoFont(size: 12, weight: .regular)
                .foregroundStyle(LitterTheme.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocalFileInspectorSheet: View {
    let file: LocalFileEntry
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onCopyPath: () -> Void
    let onCopyBotMention: () -> Void
    let onOpenTerminal: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LitterTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: file.iconName)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(file.kind == .directory ? LitterTheme.accent : LitterTheme.textSecondary)
                                .frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name)
                                    .litterFont(.headline, weight: .semibold)
                                    .foregroundStyle(LitterTheme.textPrimary)
                                    .lineLimit(2)
                                Text(file.compactMetaText)
                                    .litterMonoFont(size: 11, weight: .regular)
                                    .foregroundStyle(LitterTheme.textMuted)
                            }
                        }
                        LocalFileInfoPanel(file: file)
                        VStack(alignment: .leading, spacing: 10) {
                            LocalFileInspectorButton(title: "Preview", systemImage: "doc.text.magnifyingglass", action: { perform(onPreview) })
                            if file.isTextPreviewable {
                                LocalFileInspectorButton(title: "Edit", systemImage: "pencil", action: { perform(onEdit) })
                            }
                            LocalFileInspectorButton(title: "Copy Path", systemImage: "doc.on.doc", action: onCopyPath)
                            LocalFileInspectorButton(title: "Copy for Bot", systemImage: "bubble.left.and.text.bubble.right", action: onCopyBotMention)
                            LocalFileInspectorButton(title: "Open Terminal Here", systemImage: "terminal", action: { perform(onOpenTerminal) })
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func perform(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { action() }
    }
}

private struct LocalFileInspectorButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LitterTheme.textMuted)
            }
            .litterFont(.subheadline, weight: .semibold)
            .foregroundStyle(LitterTheme.textPrimary)
            .padding(12)
            .background(LitterTheme.surface.opacity(0.52), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LitterTerminalEntry: Identifiable, Hashable {
    let id = UUID()
    let command: String
    let directory: String
    let output: String
    let exitCode: Int32
    let duration: TimeInterval
    let date: Date

    init(command: String, directory: String, output: String, exitCode: Int32, duration: TimeInterval = 0, date: Date = Date()) {
        self.command = command
        self.directory = directory
        self.output = output
        self.exitCode = exitCode
        self.duration = duration
        self.date = date
    }
}

struct LitterTerminalPanel: View {
    let browserPath: String
    let requestedDirectory: String
    let searchQuery: String
    let onBrowse: ((String) -> Void)?
    let onCopy: (String) -> Void
    var hostTitle: String = "litter.local"
    var isLocalFilesystem: Bool = true
    var runCommand: ((String, String) async -> IshFS.Result)? = nil

    @AppStorage("litterTerminalCommandHistory") private var storedCommandHistory = ""
    @AppStorage("litterTerminalFontSize") private var terminalFontSize = 13.0
    @State private var cwd = HomeAnchor.path
    @State private var previousCwd: String?
    @State private var command = ""
    @State private var history: [LitterTerminalEntry] = []
    @State private var commandHistory: [String] = []
    @State private var commandHistoryCursor: Int?
    @State private var isRunning = false
    @State private var runningCommand: String?
    @FocusState private var inputFocused: Bool

    var visibleHistory: [LitterTerminalEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history }
        return history.filter {
            $0.command.localizedCaseInsensitiveContains(query) ||
                $0.output.localizedCaseInsensitiveContains(query) ||
                $0.directory.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider().overlay(LitterTheme.accent.opacity(0.28))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if visibleHistory.isEmpty {
                            terminalWelcome
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(visibleHistory) { item in
                                terminalEntry(item)
                                    .id(item.id)
                            }
                        }
                        if let runningCommand {
                            terminalRunningRow(runningCommand)
                                .id("terminal-running-row")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(terminalBackground)
                .onChange(of: history.count) { _, _ in
                    if let last = history.last {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: isRunning) { _, running in
                    if running {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("terminal-running-row", anchor: .bottom)
                        }
                    }
                }
            }
            terminalShortcutRail
            terminalInput
        }
        .background(terminalBackground)
        .task {
            cwd = requestedDirectory.isEmpty ? browserPath : requestedDirectory
            loadStoredCommandHistory()
            inputFocused = true
        }
        .onChange(of: requestedDirectory) { _, newValue in
            if !newValue.isEmpty { cwd = newValue }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Tab") { insertTerminalText("\t") }
                Button("~") { insertTerminalText("~") }
                Button("/") { insertTerminalText("/") }
                Button("|") { insertTerminalText(" | ") }
                Button { pasteCommandFromClipboard() } label: { Image(systemName: "doc.on.clipboard") }
                Spacer()
                Button { recallPreviousCommand() } label: { Image(systemName: "arrow.up") }
                    .disabled(commandHistory.isEmpty)
                Button { recallNextCommand() } label: { Image(systemName: "arrow.down") }
                    .disabled(commandHistory.isEmpty)
            }
        }
    }

    private var terminalHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(LitterTheme.danger).frame(width: 10, height: 10)
                    Circle().fill(LitterTheme.warning).frame(width: 10, height: 10)
                    Circle().fill(LitterTheme.success).frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hostTitle)
                        .litterMonoFont(size: 12, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text(statusLine)
                        .litterMonoFont(size: 10, weight: .regular)
                        .foregroundStyle(LitterTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                if let onBrowse {
                    terminalIconButton(systemImage: "folder", accessibilityLabel: "Browse terminal directory") {
                        onBrowse(cwd)
                    }
                }
                terminalIconButton(systemImage: "textformat.size.smaller", accessibilityLabel: "Decrease terminal font size") {
                    terminalFontSize = max(10, terminalFontSize - 1)
                }
                terminalIconButton(systemImage: "textformat.size.larger", accessibilityLabel: "Increase terminal font size") {
                    terminalFontSize = min(20, terminalFontSize + 1)
                }
                terminalIconButton(systemImage: "doc.on.clipboard", accessibilityLabel: "Paste command") {
                    pasteCommandFromClipboard()
                }
                terminalIconButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy terminal output") {
                    onCopy(transcriptText)
                }
                terminalIconButton(systemImage: "trash", accessibilityLabel: "Clear terminal") {
                    history.removeAll()
                }
            }
            Text(promptText)
                .litterMonoFont(size: 11, weight: .regular)
                .foregroundStyle(LitterTheme.accent)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(LitterTheme.codeBackground.opacity(0.98))
    }

    private var terminalInput: some View {
        VStack(spacing: 0) {
            Divider().overlay(LitterTheme.accent.opacity(0.26))
            HStack(alignment: .bottom, spacing: 10) {
                Text("#")
                    .litterMonoFont(size: 17, weight: .bold)
                    .foregroundStyle(LitterTheme.accent)
                    .padding(.bottom, 7)
                TextField("sh command", text: $command, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: CGFloat(terminalFontSize + 1), weight: .regular, design: .monospaced))
                    .lineLimit(1...5)
                    .submitLabel(.return)
                    .focused($inputFocused)
                    .onSubmit { submitCommand() }
                Button { submitCommand() } label: {
                    if isRunning {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "return")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(canSubmit ? LitterTheme.accent.opacity(0.22) : LitterTheme.surface.opacity(0.42))
                )
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(LitterTheme.codeBackground.opacity(0.98))
    }

    private var terminalShortcutRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                terminalShortcutButton(title: "Tab") { insertTerminalText("\t") }
                terminalShortcutButton(title: "~") { insertTerminalText("~") }
                terminalShortcutButton(title: "./") { insertTerminalText("./") }
                terminalShortcutButton(title: "../") { insertTerminalText("../") }
                terminalShortcutButton(title: "|") { insertTerminalText(" | ") }
                terminalShortcutButton(title: "&&") { insertTerminalText(" && ") }
                terminalShortcutButton(title: "Up", systemImage: "arrow.up") { recallPreviousCommand() }
                    .disabled(commandHistory.isEmpty)
                terminalShortcutButton(title: "Down", systemImage: "arrow.down") { recallNextCommand() }
                    .disabled(commandHistory.isEmpty)
                terminalShortcutButton(title: "Paste", systemImage: "doc.on.clipboard") { pasteCommandFromClipboard() }
                terminalCommandChip("pwd")
                terminalCommandChip("ls -la")
                terminalCommandChip("git status")
                terminalCommandChip("clear")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(LitterTheme.codeBackground.opacity(0.96))
    }

    private func terminalEntry(_ item: LitterTerminalEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(prompt(for: item.directory))
                    .litterMonoFont(size: 12, weight: .semibold)
                    .foregroundStyle(item.exitCode == 0 ? LitterTheme.accent : LitterTheme.warning)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(item.command)
                    .font(.system(size: CGFloat(terminalFontSize), weight: .semibold, design: .monospaced))
                    .foregroundStyle(LitterTheme.textPrimary)
                    .textSelection(.enabled)
                Spacer()
                Text("\(item.exitCode) \(formatDuration(item.duration))")
                    .litterMonoFont(size: 10, weight: .semibold)
                    .foregroundStyle(item.exitCode == 0 ? LitterTheme.success : LitterTheme.warning)
                terminalIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Run command again") {
                    command = item.command
                    submitCommand()
                }
                terminalIconButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy command output") {
                    onCopy(entryTranscript(item))
                }
            }
            Text(terminalAttributedOutput(item.output.isEmpty ? " " : item.output))
                .font(.system(size: CGFloat(terminalFontSize), weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func run(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        recordCommand(trimmed)
        isRunning = true
        runningCommand = trimmed
        defer {
            isRunning = false
            runningCommand = nil
            commandHistoryCursor = nil
        }
        if trimmed == "clear" {
            history.removeAll()
            return
        }
        if isCdCommand(trimmed) {
            await runCd(trimmed)
            return
        }
        let started = Date()
        let result = await executeTerminalCommand(terminalShellCommand(trimmed), cwd: cwd)
        history.append(LitterTerminalEntry(
            command: trimmed,
            directory: cwd,
            output: cleanTerminalOutput(result.output),
            exitCode: result.exitCode,
            duration: Date().timeIntervalSince(started)
        ))
    }

    private func runCd(_ command: String) async {
        let startCwd = cwd
        let started = Date()
        let target = command.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        let shellCommand: String
        if target == "-" {
            guard let previousCwd else {
                history.append(LitterTerminalEntry(
                    command: command,
                    directory: startCwd,
                    output: "cd: OLDPWD not set",
                    exitCode: 1,
                    duration: 0
                ))
                return
            }
            shellCommand = "cd \(IshFS.shellQuote(previousCwd)) && pwd"
        } else if target.isEmpty {
            shellCommand = "cd && pwd"
        } else {
            shellCommand = "cd \(target) && pwd"
        }

        let result = await executeTerminalCommand(shellCommand, cwd: startCwd)
        let output = cleanTerminalOutput(result.output)
        if result.exitCode == 0 {
            let next = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            previousCwd = startCwd
            cwd = next.isEmpty ? startCwd : next
            history.append(LitterTerminalEntry(
                command: command,
                directory: startCwd,
                output: output.isEmpty ? cwd : output,
                exitCode: 0,
                duration: Date().timeIntervalSince(started)
            ))
        } else {
            history.append(LitterTerminalEntry(
                command: command,
                directory: startCwd,
                output: output,
                exitCode: result.exitCode,
                duration: Date().timeIntervalSince(started)
            ))
        }
    }
    private var terminalBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.96),
                LitterTheme.codeBackground.opacity(0.98),
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var terminalWelcome: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Last login: \(Date().formatted(date: .abbreviated, time: .shortened)) on iSH")
                .foregroundStyle(LitterTheme.textMuted)
            Text("Alpine Linux fakefs mounted at \(HomeAnchor.path)")
                .foregroundStyle(LitterTheme.textSecondary)
            HStack(spacing: 7) {
                Text(promptText)
                    .foregroundStyle(LitterTheme.accent)
                Text("pwd")
                    .foregroundStyle(LitterTheme.textPrimary)
            }
        }
        .font(.system(size: CGFloat(terminalFontSize), weight: .regular, design: .monospaced))
        .textSelection(.enabled)
        .padding(.top, 6)
    }

    private func terminalRunningRow(_ command: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("\(promptText) \(command)")
                .litterMonoFont(size: 12, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        if let runningCommand {
            return "running \(runningCommand)"
        }
        let last = history.last
        let exit = last.map { "exit \($0.exitCode)" } ?? "ready"
        return "\(PathDisplay.display(cwd, isLocal: isLocalFilesystem)) - \(exit)"
    }

    private var promptText: String {
        prompt(for: cwd)
    }

    private var promptHost: String {
        let sanitized = hostTitle.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-").lowercased()
        return sanitized.isEmpty ? "litter" : sanitized
    }

    private var canSubmit: Bool {
        !isRunning && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var transcriptText: String {
        history.map(entryTranscript).joined(separator: "\n\n")
    }

    private func prompt(for directory: String) -> String {
        "root@\(promptHost):\(PathDisplay.display(directory, isLocal: isLocalFilesystem))#"
    }

    private func entryTranscript(_ item: LitterTerminalEntry) -> String {
        "\(prompt(for: item.directory)) \(item.command)\n\(item.output)\n[exit \(item.exitCode), \(formatDuration(item.duration))]"
    }

    private func submitCommand() {
        let pending = command
        guard !isRunning, !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        command = ""
        inputFocused = true
        Task { await run(pending) }
    }

    private func insertTerminalText(_ text: String) {
        command += text
        inputFocused = true
    }

    private func pasteCommandFromClipboard() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else { return }
        command += pasted
        inputFocused = true
    }

    private func terminalShellCommand(_ raw: String) -> String {
        "export TERM=xterm-256color COLORTERM=truecolor CLICOLOR=1 CLICOLOR_FORCE=1; \(raw)"
    }

    private func executeTerminalCommand(_ command: String, cwd: String) async -> IshFS.Result {
        if let runCommand {
            return await runCommand(command, cwd)
        }
        return await IshFS.run(command, cwd: cwd)
    }

    private func recallPreviousCommand() {
        guard !commandHistory.isEmpty else { return }
        let nextIndex: Int
        if let commandHistoryCursor {
            nextIndex = max(0, commandHistoryCursor - 1)
        } else {
            nextIndex = commandHistory.count - 1
        }
        commandHistoryCursor = nextIndex
        command = commandHistory[nextIndex]
        inputFocused = true
    }

    private func recallNextCommand() {
        guard let commandHistoryCursor else { return }
        let nextIndex = commandHistoryCursor + 1
        if nextIndex < commandHistory.count {
            self.commandHistoryCursor = nextIndex
            command = commandHistory[nextIndex]
        } else {
            self.commandHistoryCursor = nil
            command = ""
        }
        inputFocused = true
    }

    private func terminalIconButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LitterTheme.textPrimary)
                .frame(width: 30, height: 30)
                .background(LitterTheme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func terminalShortcutButton(title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text(title)
                        .litterMonoFont(size: 12, weight: .semibold)
                }
            }
            .foregroundStyle(LitterTheme.textPrimary)
            .frame(minWidth: 38, minHeight: 32)
            .padding(.horizontal, systemImage == nil ? 4 : 0)
            .background(LitterTheme.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func terminalCommandChip(_ title: String) -> some View {
        Button(title) {
            command = title
            submitCommand()
        }
        .litterMonoFont(size: 12, weight: .semibold)
        .foregroundStyle(LitterTheme.accent)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(LitterTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .buttonStyle(.plain)
    }

    private func cdDestination(from rawTarget: String) -> String {
        let trimmed = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted: String
        if trimmed.count >= 2,
           ((trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))) {
            unquoted = String(trimmed.dropFirst().dropLast())
        } else {
            unquoted = trimmed
        }
        if unquoted == "~" {
            return HomeAnchor.path
        }
        if unquoted.hasPrefix("~/") {
            return HomeAnchor.path + "/" + String(unquoted.dropFirst(2))
        }
        return unquoted
    }

    private func isCdCommand(_ raw: String) -> Bool {
        raw == "cd" || raw.hasPrefix("cd ") || raw.hasPrefix("cd\t")
    }

    private func loadStoredCommandHistory() {
        guard commandHistory.isEmpty,
              let data = storedCommandHistory.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        commandHistory = decoded
    }

    private func recordCommand(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commandHistory.removeAll { $0 == trimmed }
        commandHistory.append(trimmed)
        if commandHistory.count > 80 {
            commandHistory.removeFirst(commandHistory.count - 80)
        }
        if let data = try? JSONEncoder().encode(commandHistory),
           let encoded = String(data: data, encoding: .utf8) {
            storedCommandHistory = encoded
        }
    }

    private func cleanTerminalOutput(_ text: String) -> String {
        var output = text
        while output.last == "\n" || output.last == "\r" {
            output.removeLast()
        }
        return output
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration <= 0 { return "0ms" }
        if duration < 1 {
            return "\(max(1, Int(duration * 1000)))ms"
        }
        return String(format: "%.1fs", duration)
    }

    private func terminalAttributedOutput(_ raw: String) -> AttributedString {
        var result = AttributedString()
        var buffer = ""
        var foreground: Color?
        var bold = false
        let scalars = Array(raw.unicodeScalars)

        func flush() {
            guard !buffer.isEmpty else { return }
            var chunk = AttributedString(buffer)
            chunk.foregroundColor = foreground ?? LitterTheme.textSecondary
            if bold {
                chunk.inlinePresentationIntent = .stronglyEmphasized
            }
            result += chunk
            buffer.removeAll(keepingCapacity: true)
        }

        func applySGR(_ sequence: String) {
            let parts = sequence.isEmpty ? [0] : sequence.split(separator: ";").compactMap { Int($0) }
            for code in parts {
                switch code {
                case 0:
                    foreground = nil
                    bold = false
                case 1:
                    bold = true
                case 22:
                    bold = false
                case 39:
                    foreground = nil
                default:
                    if let color = ansiColor(code) {
                        foreground = color
                    }
                }
            }
        }

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x1B,
               index + 1 < scalars.count,
               scalars[index + 1].value == 0x5B {
                flush()
                var cursor = index + 2
                var sequence = ""
                while cursor < scalars.count, scalars[cursor].value != 0x6D {
                    sequence.unicodeScalars.append(scalars[cursor])
                    cursor += 1
                }
                if cursor < scalars.count {
                    applySGR(sequence)
                    index = cursor + 1
                    continue
                }
            }
            if scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D || scalar.value >= 0x20 {
                buffer.unicodeScalars.append(scalar)
            }
            index += 1
        }
        flush()
        return result
    }

    private func ansiColor(_ code: Int) -> Color? {
        switch code {
        case 30, 90: return LitterTheme.textMuted
        case 31, 91: return LitterTheme.danger
        case 32, 92: return LitterTheme.success
        case 33, 93: return LitterTheme.warning
        case 34, 94: return Color(hex: "#6AA9FF")
        case 35, 95: return Color(hex: "#C792EA")
        case 36, 96: return Color(hex: "#4DD0E1")
        case 37, 97: return LitterTheme.textPrimary
        default: return nil
        }
    }
}

private struct LocalFileSharePayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct LocalFileActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    init(urls: [URL]) {
        self.items = urls.map { $0 as Any }
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct LocalCommandOutput: Identifiable {
    let id = UUID()
    let title: String
    let command: String
    let exitCode: Int32
    let output: String

    init(title: String, command: String, result: IshFS.Result) {
        self.title = title
        self.command = command
        self.exitCode = result.exitCode
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        self.output = trimmed.isEmpty ? "Exit code \(result.exitCode)" : trimmed
    }
}

private struct LocalCommandOutputSheet: View {
    let output: LocalCommandOutput
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LitterTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(output.command)
                            .litterMonoFont(size: 12, weight: .semibold)
                            .foregroundStyle(LitterTheme.textSecondary)
                        Text("Exit code: \(output.exitCode)")
                            .litterMonoFont(size: 12, weight: .regular)
                            .foregroundStyle(output.exitCode == 0 ? LitterTheme.success : LitterTheme.warning)
                        Text(output.output)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(LitterTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(output.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
