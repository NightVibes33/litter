import SwiftUI

struct LocalModelAgentView: View {
    let model: LocalModelRecord
    @StateObject private var store = LocalModelAgentStore()
    @State private var prompt = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                List {
                    contextSection
                    messagesSection
                    eventsSection
                    if let error = store.lastError {
                        errorSection(error)
                    }
                }
                composer
            }
            .navigationTitle("Local Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isRunning {
                        Button("Cancel", role: .destructive) { store.cancel() }
                    } else {
                        Button("Retry") { store.retry() }
                            .disabled(store.messages.isEmpty)
                    }
                }
            }
            .sheet(item: $store.pendingApproval) { approval in
                LocalModelApprovalSheet(approval: approval) { decision in
                    store.resolveApproval(decision)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(model.fileName, systemImage: model.canRunLocally ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundColor(model.canRunLocally ? LitterTheme.success : LitterTheme.warning)
                Spacer()
                Text(model.validationStatus.displayName)
                    .litterFont(.caption, weight: .semibold)
                    .foregroundColor(LitterTheme.textSecondary)
            }
            Text("Local models are Codex-style only: quality depends on the GGUF, context size, and tool-following reliability.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
        }
        .padding()
        .background(LitterTheme.surface.opacity(0.72))
    }

    private var contextSection: some View {
        Section {
            TextEditor(text: $store.contextPathsText)
                .frame(minHeight: 74)
                .font(.system(.caption, design: .monospaced))
            Text("Enter fakefs file or folder paths, one per line or comma-separated. Files are truncated before being sent to the local model.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
        } header: {
            Text("Context")
        }
    }

    private var messagesSection: some View {
        Section {
            if store.messages.isEmpty {
                Text("Ask this local model to inspect files, explain errors, or propose small edits.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
            } else {
                ForEach(store.messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role.rawValue.uppercased())
                            .litterFont(.caption, weight: .bold)
                            .foregroundColor(color(for: message.role))
                        Text(message.text.isEmpty ? "..." : message.text)
                            .litterFont(.body)
                            .foregroundColor(LitterTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
                }
            }
        } header: {
            Text("Conversation")
        }
    }

    private var eventsSection: some View {
        Section {
            ForEach(store.events.suffix(12)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .litterFont(.caption, weight: .semibold)
                        .foregroundColor(eventColor(event.kind))
                    if !event.detail.isEmpty {
                        Text(event.detail)
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                            .lineLimit(6)
                    }
                }
                .listRowBackground(LitterTheme.surface.opacity(0.5))
            }
        } header: {
            Text("Tool Loop")
        }
    }

    private func errorSection(_ error: String) -> some View {
        Section {
            Text(error)
                .litterFont(.caption)
                .foregroundColor(LitterTheme.danger)
            Button("Retry Last Prompt") { store.retry() }
        } header: {
            Text("Recovery")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask local model...", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
            Button {
                let text = prompt
                prompt = ""
                store.send(prompt: text, model: model)
            } label: {
                Image(systemName: store.isRunning ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(store.isRunning || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(LitterTheme.surface.opacity(0.96))
    }

    private func color(for role: LocalModelAgentMessage.Role) -> Color {
        switch role {
        case .user: return LitterTheme.accent
        case .assistant: return LitterTheme.textPrimary
        case .tool: return LitterTheme.warning
        case .system: return LitterTheme.textMuted
        case .error: return LitterTheme.danger
        }
    }

    private func eventColor(_ kind: LocalModelAgentEvent.Kind) -> Color {
        switch kind {
        case .failed: return LitterTheme.danger
        case .approval, .retry: return LitterTheme.warning
        case .completed: return LitterTheme.success
        default: return LitterTheme.textSecondary
        }
    }
}

struct LocalModelApprovalSheet: View {
    let approval: LocalModelAgentApprovalState
    let onDecision: (LocalModelToolApprovalDecision) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Request") {
                    Text(approval.request.reason)
                    Text(approval.request.call.arguments.description)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let diff = approval.diffPreview {
                    Section("Diff Preview") {
                        Text(diff)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                Section("Decision") {
                    Button("Deny", role: .destructive) {
                        onDecision(.denied)
                        dismiss()
                    }
                    if approval.request.risk == .shell {
                        Button("Allow Shell Once") {
                            onDecision(.approveShellReadOnly)
                            dismiss()
                        }
                    }
                    if approval.request.risk == .write {
                        Button("Apply Write") {
                            onDecision(.approveWrite)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Approve Local Tool")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
