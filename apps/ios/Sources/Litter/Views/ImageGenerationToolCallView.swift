import Nuke
import NukeUI
import SwiftUI
import UIKit

struct ImageGenerationToolCallView: View {
    let data: ConversationImageGenerationData
    private let externalExpanded: Bool?
    @State private var expanded: Bool
    @State private var promptExpanded = false
    @State private var showShareSheet = false
    /// Header row (icon + summary). A half-step smaller than body so tool
    /// calls read as secondary to assistant messages.
    private let summaryFontSize: CGFloat = 13
    /// Expanded content size — matches the bash/command output size
    /// (`ConversationCommandOutputViewport` renders at 12pt) so tool-call
    /// details share a typographic baseline with terminal output.
    private let contentFontSize: CGFloat = 12

    init(
        data: ConversationImageGenerationData,
        externalExpanded: Bool? = nil
    ) {
        self.data = data
        self.externalExpanded = externalExpanded
        _expanded = State(initialValue: externalExpanded ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    imagePreview
                    if let prompt = data.revisedPrompt, !prompt.isEmpty {
                        promptBlock(prompt)
                    }
                }
                .padding(.top, 6)
                .transition(.sectionReveal)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(LitterTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LitterTheme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(duration: 0.32, bounce: 0.12), value: expanded)
        .onChange(of: externalExpanded) { _, newValue in
            if let newValue, newValue != expanded {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    expanded = newValue
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .litterFont(size: 12, weight: .semibold)
                .foregroundColor(LitterTheme.accent)

            Text(summary)
                .litterFont(size: summaryFontSize)
                .foregroundColor(LitterTheme.textSystem)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if data.isInProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(LitterTheme.accent)
            }

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .litterFont(size: 11, weight: .medium)
                .foregroundColor(LitterTheme.textMuted)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        }
    }

    private var summary: String {
        switch data.status {
        case .completed: return "Generated image"
        case .failed: return "Image generation failed"
        default: return "Generating image…"
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let bytes = data.imagePNG {
            let cacheKey = "image-gen-\(bytes.count)-\(bytes.hashValue)"
            LazyImage(
                request: ImageRequest(
                    id: cacheKey,
                    data: { bytes },
                    processors: [
                        ImageProcessors.Resize(
                            size: CGSize(width: 1200, height: 1200),
                            unit: .points,
                            contentMode: .aspectFit
                        )
                    ]
                )
            ) { state in
                if let image = state.image, let ui = state.imageContainer?.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(LitterTheme.border.opacity(0.4), lineWidth: 0.5)
                        )
                        .draggable(Image(uiImage: ui)) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.image = ui
                            } label: {
                                Label("Copy Image", systemImage: "doc.on.doc")
                            }
                            Button {
                                showShareSheet = true
                            } label: {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
                        }
                        .sheet(isPresented: $showShareSheet) {
                            ShareSheet(items: [ui])
                        }
                }
            }
        } else if data.isInProgress {
            ImageGenerationLoadingTile()
        } else if data.status == .failed {
            placeholderTile(icon: "exclamationmark.triangle.fill", message: "Image unavailable", tone: LitterTheme.danger)
        } else {
            placeholderTile(icon: "photo", message: "Image unavailable", tone: LitterTheme.textSecondary)
        }
    }

    private func promptBlock(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("REVISED PROMPT")
                    .litterFont(.caption2, weight: .bold)
                    .foregroundColor(LitterTheme.textSecondary)
                Spacer()
                if shouldShowPromptToggle(prompt) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            promptExpanded.toggle()
                        }
                    } label: {
                        Text(promptExpanded ? "Show less" : "Show more")
                            .litterFont(.caption2, weight: .medium)
                            .foregroundColor(LitterTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(promptExpanded ? prompt : collapsedPreview(prompt))
                .litterFont(size: contentFontSize)
                .foregroundColor(LitterTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LitterTheme.codeBackground.opacity(0.82))
                )
        }
    }

    private func placeholderTile(icon: String, message: String, tone: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .litterFont(size: 24, weight: .medium)
                .foregroundColor(tone)
            Text(message)
                .litterFont(.caption)
                .foregroundColor(tone)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LitterTheme.codeBackground.opacity(0.82))
        )
    }

    private func shouldShowPromptToggle(_ prompt: String) -> Bool {
        prompt.count > 220 || prompt.split(separator: "\n", omittingEmptySubsequences: false).count > 4
    }

    private func collapsedPreview(_ text: String) -> String {
        let limit = 220
        if text.count <= limit { return text }
        let head = String(text.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return head + "…"
    }
}

private struct ImageGenerationLoadingTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LitterTheme.accent.opacity(pulse ? 0.18 : 0.08))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(LitterTheme.accent.opacity(0.32), lineWidth: 0.5)
                    )

                Image(systemName: "sparkles")
                    .litterFont(size: 19, weight: .semibold)
                    .foregroundColor(LitterTheme.accent)
                    .scaleEffect(pulse ? 1.06 : 0.96)
            }

            VStack(spacing: 5) {
                Text("Generating image")
                    .litterFont(.caption, weight: .semibold)
                    .foregroundColor(LitterTheme.textSystem)

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(LitterTheme.accent.opacity(0.42))
                            .frame(width: index == 1 ? 42 : 28, height: 4)
                            .opacity(pulse ? 1.0 - Double(index) * 0.18 : 0.38 + Double(index) * 0.16)
                    }
                }
                .frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LitterTheme.codeBackground.opacity(0.82))
        )
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
