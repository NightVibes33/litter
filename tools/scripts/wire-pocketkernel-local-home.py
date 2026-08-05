#!/usr/bin/env python3
from pathlib import Path
import re


def sub(path: str, pattern: str, replacement: str, count: int = 1, flags: int = 0) -> None:
    file_path = Path(path)
    text = file_path.read_text()
    next_text, matches = re.subn(pattern, replacement, text, count=count, flags=flags)
    if matches != count:
        raise SystemExit(
            f"expected {count} match(es), got {matches}: {path} / {pattern[:120]}"
        )
    file_path.write_text(next_text)


models = "apps/ios/Sources/Litter/Models/AIProviderModels.swift"
store = "apps/ios/Sources/Litter/Models/AIProviderStore.swift"
home = "apps/ios/Sources/Litter/Views/HomeComposerView.swift"
chip = "apps/ios/Sources/Litter/Views/HomeModelChip.swift"

sub(
    models,
    r"(static let defaults = GlobalModelSettings\(\s*routingMode:) \.automatic",
    r"\1 .appleIntelligence",
)
sub(
    store,
    r"(case \.automatic:\s*)return appleIntelligenceProvider != nil",
    r"\1return false",
)

sub(
    home,
    r"(@Environment\(AppState\.self\) private var appState\n)",
    r"\1    @StateObject private var providerStore = AIProviderStore.shared\n",
)
sub(
    home,
    r"(@State private var showRemoteFilePicker = false\n)",
    r"\1    @State private var showAppleIntelligenceChat = false\n    @State private var pendingApplePrompt: String?\n",
)
sub(
    home,
    r"private var isDisabled: Bool \{ project == nil \}",
    "private var isDisabled: Bool {\n        project == nil && !providerStore.shouldUseAppleIntelligence\n    }",
)
sub(
    home,
    r"(\.fullScreenCover\(isPresented: \$showCamera\) \{\s*CameraView\(image: \$capturedImage\)\s*\.ignoresSafeArea\(\)\s*\}\s*)(\.task \{)",
    r"\1.fullScreenCover(isPresented: $showAppleIntelligenceChat) {\n            NavigationStack {\n                AppleIntelligenceChatView(initialPrompt: pendingApplePrompt)\n            }\n        }\n        \2",
    flags=re.S,
)
sub(
    home,
    r'''guard !isSubmitting else \{ return \}\s*guard let project else \{\s*errorMessage = "Pick a project before sending\."\s*return\s*\}\s*isSubmitting = true''',
    '''guard !isSubmitting else { return }

        if providerStore.shouldUseAppleIntelligence {
            guard pendingAttachments.isEmpty else {
                errorMessage = "File and image tools are not wired to the on-device model yet. Send text only or use a Codex server for attachments."
                return
            }
            guard !text.isEmpty else {
                errorMessage = "Enter a message for Apple Intelligence."
                return
            }
            pendingApplePrompt = text
            inputText = ""
            composerSelectionRange = NSRange(location: 0, length: 0)
            isComposerFocused = false
            errorMessage = nil
            showAppleIntelligenceChat = true
            return
        }

        guard let project else {
            errorMessage = "Pick a project before sending, or select Apple Intelligence in AI Providers."
            return
        }

        isSubmitting = true''',
    flags=re.S,
)

sub(
    chip,
    r"(@AppStorage\(\"fastMode\"\) private var fastMode = false\n)",
    r"\1    @StateObject private var providerStore = AIProviderStore.shared\n",
)
sub(
    chip,
    r"(@State private var showSheet = false\n)",
    r"\1    @State private var showAppleIntelligenceChat = false\n",
)
sub(
    chip,
    r"Button \{\s*selectedDetent = \.large\s*showSheet = true\s*\} label:",
    """Button {
            if providerStore.shouldUseAppleIntelligence {
                showAppleIntelligenceChat = true
            } else {
                selectedDetent = .large
                showSheet = true
            }
        } label:""",
    flags=re.S,
)
sub(
    chip,
    r"(private var selectedModelLabel: String \{\n)",
    r"\1        if providerStore.shouldUseAppleIntelligence { return \"Apple Intelligence\" }\n",
)
sub(
    chip,
    r"\.disabled\(disabled\)\s*\.opacity\(disabled \? 0\.5 : 1\)",
    ".disabled(disabled && !providerStore.shouldUseAppleIntelligence)\n        .opacity(disabled && !providerStore.shouldUseAppleIntelligence ? 0.5 : 1)",
)
sub(
    chip,
    r"(\.onChange\(of: showSheet\))",
    ".fullScreenCover(isPresented: $showAppleIntelligenceChat) {\n            NavigationStack { AppleIntelligenceChatView() }\n        }\n        \\1",
)
sub(
    chip,
    r"(\.task\(id: serverId\) \{\n\s*)(guard let serverId else \{ return \})",
    r"\1guard !providerStore.shouldUseAppleIntelligence else { return }\n            \2",
)

workflow = Path(".github/workflows/wire-pocketkernel-local-home-v3.yml")
if workflow.exists():
    workflow.unlink()
