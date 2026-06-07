import SwiftUI
import UIKit

struct AppIconSettingsView: View {
    @State private var proStore = ProAccessStore.shared
    @State private var currentIconName: String?
    @State private var lockedOption: AlleyCatAppIcon?
    @State private var isApplying = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LitterTheme.backgroundGradient.ignoresSafeArea()
            Form {
                Section {
                    ForEach(AlleyCatAppIcon.allCases) { option in
                        Button {
                            select(option)
                        } label: {
                            HStack(spacing: 12) {
                                iconPreview(option)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(option.title)
                                            .litterFont(.subheadline, weight: .semibold)
                                            .foregroundStyle(LitterTheme.textPrimary)
                                        if option.showsProBadge && option.requiresPro && !proStore.hasProAccess {
                                            Text("Pro")
                                                .litterFont(.caption2, weight: .bold)
                                                .foregroundStyle(LitterTheme.textOnAccent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(LitterTheme.accent, in: Capsule())
                                        }
                                    }
                                    if !option.subtitle.isEmpty {
                                        Text(option.subtitle)
                                            .litterFont(.caption)
                                            .foregroundStyle(LitterTheme.textSecondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if currentIconName == option.alternateIconName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(LitterTheme.accent)
                                } else if option.requiresPro && !proStore.hasProAccess {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(LitterTheme.textMuted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                        .listRowBackground(LitterTheme.surface.opacity(0.6))
                    }
                } header: {
                    Text("App Icon")
                        .foregroundStyle(LitterTheme.textSecondary)
                } footer: {
                    Text("iOS applies icon changes after its system confirmation prompt. If the Home Screen does not refresh right away, reopen Alley Cãt.")
                        .foregroundStyle(LitterTheme.textMuted)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .litterFont(.caption)
                            .foregroundStyle(LitterTheme.accent)
                            .listRowBackground(LitterTheme.surface.opacity(0.6))
                    }
                }
            }
            .scrollContentBackground(.hidden)

            if isApplying {
                Color.black.opacity(0.28).ignoresSafeArea()
                ProgressView()
                    .tint(LitterTheme.accent)
                    .scaleEffect(1.15)
            }
        }
        .navigationTitle("Icon Switcher")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await proStore.loadProducts()
            currentIconName = AlleyCatAppIcon.currentRuntimeIconName()
        }
        .sheet(item: $lockedOption) { option in
            NavigationStack {
                ProPaywallView(feature: .appearance) {
                    lockedOption = nil
                    select(option)
                }
            }
        }
        .alert("Icon Change Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unable to change the app icon.")
        }
    }

    private func iconPreview(_ option: AlleyCatAppIcon) -> some View {
        Image(option.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(LitterTheme.border.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            .accessibilityHidden(true)
    }

    private func select(_ option: AlleyCatAppIcon) {
        statusMessage = nil
        guard currentIconName != option.alternateIconName else { return }
        guard !option.requiresPro || proStore.hasProAccess else {
            lockedOption = option
            return
        }
        apply(option)
    }

    private func apply(_ option: AlleyCatAppIcon) {
        guard AlleyCatAppIcon.supportsAlternateIcons else {
            errorMessage = "Alternate app icons are not available on this device or platform."
            return
        }

        isApplying = true
        AlleyCatAppIcon.apply(option) { error in
            Task { @MainActor in
                isApplying = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    currentIconName = option.alternateIconName
                    statusMessage = "Selected \(option.title)."
                }
            }
        }
    }
}

private enum AlleyCatAppIcon: String, CaseIterable, Identifiable {
    case current
    case original
    case shinobi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: return "Alley Cãt"
        case .original: return "Original Icon"
        case .shinobi: return "Shinobi Cats"
        }
    }

    var subtitle: String {
        switch self {
        case .current: return "Current cats-in-box icon"
        case .original: return ""
        case .shinobi: return "Hidden village cats"
        }
    }

    var assetName: String {
        switch self {
        case .current: return "app_icon_current"
        case .original: return "app_icon_original"
        case .shinobi: return "app_icon_shinobi"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .current: return nil
        case .original: return "AppIconOriginal"
        case .shinobi: return "AppIconShinobi"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .current: return false
        case .original, .shinobi: return true
        }
    }

    var showsProBadge: Bool {
        switch self {
        case .current, .original: return false
        case .shinobi: return true
        }
    }

    static var supportsAlternateIcons: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        UIApplication.shared.supportsAlternateIcons
        #else
        false
        #endif
    }

    @MainActor
    static func currentRuntimeIconName() -> String? {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        UIApplication.shared.alternateIconName
        #else
        nil
        #endif
    }

    @MainActor
    static func apply(_ option: AlleyCatAppIcon, completion: @escaping (Error?) -> Void) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        UIApplication.shared.setAlternateIconName(option.alternateIconName, completionHandler: completion)
        #else
        completion(nil)
        #endif
    }
}
