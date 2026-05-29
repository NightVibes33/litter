import SwiftUI
import UniformTypeIdentifiers

struct MountedFoldersView: View {
    enum PickerMode: Equatable {
        case add
        case reconnect(UUID)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var store = UserMountStore.shared
    @State private var pickerMode: PickerMode?
    @State private var pendingRemoval: UserMount?
    @State private var containerMountStatus: MountStatus?
    @State private var isMountingContainer = false

    var body: some View {
        NavigationStack {
            ZStack {
                LitterTheme.backgroundGradient.ignoresSafeArea()
                list
            }
            .navigationTitle("Mounted folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LitterTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await mountNativeContainer() }
                        } label: {
                            Label(containerMountStatus == .mounted ? "Remount App Container" : "Mount App Container", systemImage: "internaldrive")
                        }
                        Button {
                            pickerMode = .add
                        } label: {
                            Label("Add Folder", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundColor(LitterTheme.accent)
                }
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { pickerMode != nil },
                set: { if !$0 { pickerMode = nil } }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            let mode = pickerMode
            pickerMode = nil
            handlePick(result: result, mode: mode)
        }
        .confirmationDialog(
            removalPrompt,
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { mount in
            Button("Remove", role: .destructive) {
                Task { await store.remove(id: mount.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await refreshNativeContainerStatus()
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                nativeContainerRow
                if store.mounts.isEmpty {
                    noUserMountsNote
                } else {
                    ForEach(store.mounts) { mount in
                        row(for: mount)
                    }
                }
                footerExplainer
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var nativeContainerRow: some View {
        let status = containerMountStatus
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                statusIcon(for: status)
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Container")
                        .litterFont(.subheadline)
                        .foregroundColor(LitterTheme.textPrimary)
                    Text(IshFS.nativeContainerMountPath)
                        .litterMonoFont(size: 11)
                        .foregroundColor(LitterTheme.textMuted)
                }
                Spacer()
                Menu {
                    Button {
                        Task { await mountNativeContainer() }
                    } label: {
                        Label(status == .mounted ? "Remount App Container" : "Mount App Container", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await refreshNativeContainerStatus() }
                    } label: {
                        Label("Check Status", systemImage: "checkmark.circle")
                    }
                } label: {
                    Group {
                        if isMountingContainer {
                            ProgressView()
                                .tint(LitterTheme.textSecondary)
                        } else {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(LitterTheme.textSecondary)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .disabled(isMountingContainer)
            }
            Text(NSHomeDirectory())
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
            if let detail = statusDetail(for: status) {
                Text(detail)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.danger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LitterTheme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LitterTheme.textMuted.opacity(0.18), lineWidth: 0.6)
        )
    }

    private func row(for mount: UserMount) -> some View {
        let status = store.statuses[mount.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                statusIcon(for: status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mount.name)
                        .litterFont(.subheadline)
                        .foregroundColor(LitterTheme.textPrimary)
                    Text("/mnt/\(mount.name)")
                        .litterMonoFont(size: 11)
                        .foregroundColor(LitterTheme.textMuted)
                }
                Spacer()
                Menu {
                    if needsReconnect(status) {
                        Button {
                            pickerMode = .reconnect(mount.id)
                        } label: {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                        }
                    }
                    Button(role: .destructive) {
                        pendingRemoval = mount
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(LitterTheme.textSecondary)
                }
            }
            Text(mount.displayPath)
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
            if let detail = statusDetail(for: status) {
                Text(detail)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.danger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LitterTheme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LitterTheme.textMuted.opacity(0.18), lineWidth: 0.6)
        )
    }

    private var noUserMountsNote: some View {
        Text("No extra user folders mounted. Pick a folder from Files to make it available inside iSH at /mnt/<name>.")
            .litterFont(.caption)
            .foregroundColor(LitterTheme.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    private var footerExplainer: some View {
        Text("Mounts persist across launches. Removing only detaches the mount inside iSH; files in the source folder are not deleted.")
            .litterFont(.caption)
            .foregroundColor(LitterTheme.textMuted)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }

    // MARK: - Helpers

    @MainActor
    private func refreshNativeContainerStatus() async {
        let result = await IshFS.nativeContainerMountStatus()
        containerMountStatus = result.exitCode == 0 ? .mounted : nil
    }

    @MainActor
    private func mountNativeContainer() async {
        guard !isMountingContainer else { return }
        isMountingContainer = true
        let result = await IshFS.repairNativeContainerBridge()
        containerMountStatus = mountStatus(from: result, fallback: "mount -t real returned \(result.exitCode)")
        isMountingContainer = false
    }

    private func mountStatus(from result: IshFS.Result, fallback: String) -> MountStatus {
        guard result.exitCode != 0 else { return .mounted }
        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return .mountFailed(rc: result.exitCode, message: message.isEmpty ? fallback : message)
    }

    private func handlePick(result: Result<[URL], Error>, mode: PickerMode?) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                switch mode {
                case .reconnect(let id):
                    await store.reconnect(id: id, newUrl: url)
                case .add, .none:
                    await store.addByPicking(url: url)
                }
            }
        case .failure(let error):
            LLog.warn("mount", "file picker failed", fields: ["error": String(describing: error)])
        }
    }

    private func statusIcon(for status: MountStatus?) -> some View {
        let (symbol, tint): (String, Color) = {
            switch status {
            case .mounted:
                return ("checkmark.circle.fill", LitterTheme.accent)
            case .resolutionFailed, .mountFailed:
                return ("exclamationmark.triangle.fill", LitterTheme.danger)
            case nil:
                return ("circle.dotted", LitterTheme.textMuted)
            }
        }()
        return Image(systemName: symbol)
            .foregroundColor(tint)
            .frame(width: 18)
    }

    private func statusDetail(for status: MountStatus?) -> String? {
        switch status {
        case .resolutionFailed(let message):
            return "Couldn't reach this folder: \(message)"
        case .mountFailed(let rc, let message):
            return "Mount failed (rc=\(rc)): \(message)"
        case .mounted, nil:
            return nil
        }
    }

    private func needsReconnect(_ status: MountStatus?) -> Bool {
        switch status {
        case .resolutionFailed, .mountFailed: return true
        case .mounted, nil: return false
        }
    }

    private var removalPrompt: String {
        if let pendingRemoval {
            return "Remove \(pendingRemoval.name)?"
        }
        return "Remove mount?"
    }
}

#if DEBUG
#Preview {
    MountedFoldersView()
}
#endif
