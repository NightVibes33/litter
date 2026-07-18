import SwiftUI
import UIKit

struct BuildArtifactShareCard: View {
    let artifact: BuildArtifact
    @State private var isPreparing = false
    @State private var sharePayload: BuildArtifactSharePayload?
    @State private var errorMessage: String?
    @State private var sizeText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .litterFont(size: 16, weight: .semibold)
                    .foregroundColor(LitterTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(LitterTheme.accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.kind.title)
                        .litterFont(.caption, weight: .semibold)
                        .foregroundColor(LitterTheme.textPrimary)
                    Text(artifact.fileName)
                        .litterMonoFont(size: 11)
                        .foregroundColor(LitterTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sizeText ?? artifact.path)
                        .litterFont(.caption2)
                        .foregroundColor(LitterTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Button {
                    Task { await prepareShare() }
                } label: {
                    Label(isPreparing ? "Preparing" : "Share", systemImage: isPreparing ? "hourglass" : "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(LitterTheme.accent)
                .disabled(isPreparing)
                .accessibilityLabel("Share unsigned IPA")
            }

            if let errorMessage {
                Text(errorMessage)
                    .litterFont(.caption2)
                    .foregroundColor(LitterTheme.danger)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(LitterTheme.surface.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LitterTheme.accent.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task { await refreshSize() }
        .sheet(item: $sharePayload) { payload in
            ArtifactActivitySheet(items: [payload.url])
        }
    }

    private func refreshSize() async {
        guard sizeText == nil, let size = try? await IshFS.fileSize(path: artifact.path) else { return }
        await MainActor.run {
            sizeText = "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) at \(artifact.path)"
        }
    }

    private func prepareShare() async {
        await MainActor.run {
            isPreparing = true
            errorMessage = nil
        }
        do {
            let url = try await IshFS.copyFileToTemporaryURL(path: artifact.path, suggestedFileName: artifact.fileName)
            await MainActor.run {
                sharePayload = BuildArtifactSharePayload(url: url)
                isPreparing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isPreparing = false
            }
        }
    }
}

private struct BuildArtifactSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ArtifactActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
