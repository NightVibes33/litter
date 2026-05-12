import SwiftUI
import UIKit

struct DiagnosticsBundleView: View {
    @State private var bundleText = ""
    @State private var isCollecting = false
    @State private var sharePayload: DiagnosticsSharePayload?

    @StateObject private var taskBag = ViewTaskBag()
    var body: some View {
        List {
            Section {
                Button {
                    taskBag.run { await collect() }
                } label: {
                    Label(isCollecting ? "Collecting..." : "Collect Recovery Bundle", systemImage: "cross.case.fill")
                        .foregroundStyle(LitterTheme.accent)
                }
                .disabled(isCollecting)
                .listRowBackground(LitterTheme.surface.opacity(0.6))

                if !bundleText.isEmpty {
                    Button {
                        UIPasteboard.general.string = bundleText
                    } label: {
                        Label("Copy Bundle", systemImage: "doc.on.doc")
                            .foregroundStyle(LitterTheme.accent)
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))

                    Button {
                        shareBundle()
                    } label: {
                        Label("Share Bundle", systemImage: "square.and.arrow.up")
                            .foregroundStyle(LitterTheme.accent)
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
                }
            } header: {
                Text("Recovery")
                    .foregroundStyle(LitterTheme.textSecondary)
            } footer: {
                Text("Bundles include app/runtime status and the last 200 in-memory log lines after token redaction.")
            }

            Section {
                if bundleText.isEmpty {
                    Text("No recovery bundle collected yet.")
                        .foregroundStyle(LitterTheme.textSecondary)
                        .listRowBackground(LitterTheme.surface.opacity(0.6))
                } else {
                    Text(bundleText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(LitterTheme.textPrimary)
                        .textSelection(.enabled)
                        .listRowBackground(LitterTheme.surface.opacity(0.6))
                }
            } header: {
                Text("Bundle Preview")
                    .foregroundStyle(LitterTheme.textSecondary)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
        .sheet(item: $sharePayload) { payload in
            DiagnosticsActivitySheet(url: payload.url)
        }
        .task {
            if bundleText.isEmpty {
                await collect()
            }
        }
        .onDisappear { taskBag.cancelAll() }
    }

    @MainActor
    private func collect() async {
        guard !isCollecting else { return }
        isCollecting = true
        defer { isCollecting = false }
        bundleText = await DiagnosticsBundleBuilder.build()
    }

    private func shareBundle() {
        guard !bundleText.isEmpty else { return }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("LitterDiagnostics-\(UUID().uuidString).txt")
            try LLog.redact(bundleText).write(to: url, atomically: true, encoding: .utf8)
            sharePayload = DiagnosticsSharePayload(url: url)
        } catch {
            LLog.error("diagnostics", "failed to write diagnostics bundle", error: error)
        }
    }
}

private enum DiagnosticsBundleBuilder {
    @MainActor
    static func build() async -> String {
        var lines: [String] = []
        lines.append("Litter Recovery Bundle")
        lines.append("Collected: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("App")
        lines.append("- Version: \(bundleValue("CFBundleShortVersionString"))")
        lines.append("- Build: \(bundleValue("CFBundleVersion"))")
        lines.append("- Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
        lines.append("")
        lines.append("Device")
        lines.append("- Name: \(UIDevice.current.name)")
        lines.append("- Model: \(UIDevice.current.model)")
        lines.append("- System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        lines.append("")
        lines.append("Local Runtime")
        do {
            try await LitterPlatform.ensureLocalRuntimeReady()
            lines.append("- iSH readiness: ready")
        } catch {
            lines.append("- iSH readiness: \(error.localizedDescription)")
        }
        lines.append("")
        lines.append("BuildKit")
        let status = await LitterBuildKit.shared.status()
        lines.append("- Readiness: \(status.readinessTitle)")
        lines.append("- Detail: \(status.readinessDetail)")
        lines.append("- Shims: \(status.commandShimsInstalled ? "installed" : "missing")")
        lines.append("- Monitor: \(status.requestMonitorRunning ? "running" : "stopped")")
        lines.append("- Private assets: \(status.privateAssetsInstalled ? "installed" : "missing")")
        lines.append("- Native driver loadable: \(status.nativeDriverLoadable ? "yes" : "no")")
        if !status.missingRequirements.isEmpty {
            lines.append("- Missing: \(status.missingRequirements.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("Recent Logs")
        let recent = LLog.recentRedactedLines(limit: 200)
        if recent.isEmpty {
            lines.append("- no in-memory log lines captured")
        } else {
            lines.append(contentsOf: recent)
        }
        return LLog.redact(lines.joined(separator: "\n")) + "\n"
    }

    private static func bundleValue(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "unknown"
    }
}

private struct DiagnosticsSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DiagnosticsActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
