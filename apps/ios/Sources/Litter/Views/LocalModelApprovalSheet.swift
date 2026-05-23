import SwiftUI

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

                    if approval.request.risk == .shell || approval.request.risk == .build {
                        Button(approval.request.risk == .build ? "Run Build Once" : "Allow Shell Once") {
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
