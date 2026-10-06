import SwiftUI

struct LockScreenCardView: View {
    let prompt: String
    let model: String
    let cwd: String
    let state: CodexTurnAttributes.ContentState
    let timerContent: AnyView

    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color { LitterPalette.surface.color(for: colorScheme) }
    private var logoBackground: Color { LitterPalette.surfaceLight.color(for: colorScheme) }
    private var primaryText: Color { LitterPalette.textPrimary.color(for: colorScheme) }
    private var secondaryText: Color { LitterPalette.textSecondary.color(for: colorScheme) }
    private var tertiaryText: Color { LitterPalette.textMuted.color(for: colorScheme) }
    private var mutedText: Color { tertiaryText.opacity(0.7) }
    private var chipBgBase: Color { colorScheme == .dark ? .white : .black }
    private var completedBadgeFg: Color { secondaryText }
    private var dangerText: Color { LitterPalette.danger.color(for: colorScheme) }
    private var warningText: Color { LitterPalette.warning.color(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image("brand_logo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(logoBackground)
                    )

                Text(prompt)
                    .font(.system(size: 13, weight: .medium, design: LitterPalette.fontDesign))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                timerContent
                    .frame(width: 52, alignment: .trailing)
            }

            Text(displayText)
                .font(.system(size: 11, design: LitterPalette.fontDesign))
                .foregroundStyle(snippetColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.leading, 38)

            HStack(spacing: 0) {
                phaseBadge

                Text(model)
                    .font(.system(size: 10, design: LitterPalette.fontDesign))
                    .foregroundStyle(tertiaryText)
                    .padding(.leading, 8)

                Spacer(minLength: 4)

                if state.fileChangeCount > 0 {
                    metaChip(systemImage: "doc.text", text: "\(state.fileChangeCount)")
                }
                if state.toolCallCount > 0 {
                    metaChip(systemImage: "chevron.left.forwardslash.chevron.right", text: "\(state.toolCallCount)")
                }
                if let pushCount = state.pushCount, pushCount > 0 {
                    metaChip(systemImage: "antenna.radiowaves.left.and.right", text: "\(pushCount)")
                }

                metaChip(systemImage: "folder", text: cwdShortened)

                if state.contextPercent > 0 {
                    ctxBadge
                        .padding(.leading, 4)
                }
            }
            .padding(.top, 8)
            .padding(.leading, 38)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var displayText: String {
        if let snippet = state.outputSnippet, !snippet.isEmpty { return snippet }
        switch state.phase {
        case .thinking: return "Thinking..."
        case .toolCall: return state.toolName ?? "Running tool..."
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }

    private var snippetColor: Color {
        if state.outputSnippet != nil { return secondaryText }
        switch state.phase {
        case .thinking, .toolCall: return warningText.opacity(0.7)
        case .completed: return secondaryText
        case .failed: return dangerText.opacity(0.7)
        }
    }

    private var phaseBadge: some View {
        let text: String = {
            switch state.phase {
            case .thinking: return "thinking"
            case .toolCall: return "tool"
            case .completed: return "done"
            case .failed: return "failed"
            }
        }()
        let fg: Color = {
            switch state.phase {
            case .thinking, .toolCall: return warningText
            case .completed: return completedBadgeFg
            case .failed: return dangerText
            }
        }()
        let bg: Color = {
            switch state.phase {
            case .thinking, .toolCall: return warningText.opacity(colorScheme == .dark ? 0.12 : 0.15)
            case .completed: return chipBgBase.opacity(0.06)
            case .failed: return dangerText.opacity(colorScheme == .dark ? 0.12 : 0.15)
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .medium, design: LitterPalette.fontDesign))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(bg))
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
                .foregroundStyle(mutedText)
            Text(text)
                .font(.system(size: 10, design: LitterPalette.fontDesign))
                .foregroundStyle(tertiaryText)
                .lineLimit(1)
        }
        .padding(.trailing, 10)
    }

    private var ctxBadge: some View {
        let percent = state.contextPercent
        let fg: Color = percent >= 80 ? dangerText : percent >= 60 ? warningText : tertiaryText
        let bg: Color = percent >= 80 ? dangerText.opacity(0.1) : percent >= 60 ? warningText.opacity(0.1) : chipBgBase.opacity(0.05)
        return Text("\(percent)%")
            .font(.system(size: 9, weight: .semibold, design: LitterPalette.fontDesign))
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(bg))
    }

    private var cwdShortened: String {
        guard !cwd.isEmpty else { return "~" }
        if let last = cwd.split(separator: "/").last { return String(last) }
        return cwd
    }
}
