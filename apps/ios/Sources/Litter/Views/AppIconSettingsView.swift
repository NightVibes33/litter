import SwiftUI
import UIKit
import MachO

struct AppIconSettingsView: View {
    @State private var proStore = ProAccessStore.shared
    @State private var currentIconName: String?
    @State private var lockedOption: AlleyCatAppIcon?
    @State private var isApplying = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AlleyBackdrop().ignoresSafeArea()
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
                        .listRowBackground(LitterTheme.surface.opacity(0.88))
                    }
                } header: {
                    Text("App Icon")
                        .foregroundStyle(LitterTheme.textSecondary)
                } footer: {
                    Text("iOS applies icon changes after its system confirmation prompt. If the Home Screen does not refresh right away, reopen Alley Cãt.")
                        .foregroundStyle(LitterTheme.textMuted)
                }

                if AlleyCatAppIcon.isRunningInLiveContainer {
                    Section {
                        Label {
                            Text("Icon switching is not available while Alley Cãt is running inside LiveContainer.")
                                .litterFont(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(LitterTheme.textSecondary)
                        .listRowBackground(LitterTheme.surface.opacity(0.88))
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .litterFont(.caption)
                            .foregroundStyle(LitterTheme.accent)
                            .listRowBackground(LitterTheme.surface.opacity(0.88))
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
        guard !AlleyCatAppIcon.isRunningInLiveContainer else {
            errorMessage = AlleyCatAppIcon.liveContainerUnsupportedMessage
            return
        }
        guard AlleyCatAppIcon.supportsAlternateIcons else {
            errorMessage = "Alternate app icons are not available on this device or platform."
            return
        }

        isApplying = true
        AlleyCatAppIcon.apply(option) { error in
            Task { @MainActor in
                isApplying = false
                if let error {
                    errorMessage = AlleyCatAppIcon.message(for: error)
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
    case electricPulse
    case oceanConnect
    case devinePurple
    case greenTerminal
    case cosmicForum
    case crystalFrost
    case cyberDistrict
    case midnightAMOLED
    case rgbArena
    case neuralCore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: return "Alley Cãt"
        case .original: return "Original Icon"
        case .shinobi: return "Shinobi Cats"
        case .electricPulse: return "Electric Pulse"
        case .oceanConnect: return "Ocean Connect"
        case .devinePurple: return "Devine Purple"
        case .greenTerminal: return "Green Terminal"
        case .cosmicForum: return "Cosmic Forum"
        case .crystalFrost: return "Crystal Frost"
        case .cyberDistrict: return "Cyber District"
        case .midnightAMOLED: return "Midnight AMOLED"
        case .rgbArena: return "RGB Arena"
        case .neuralCore: return "Neural Core"
        }
    }

    var subtitle: String {
        switch self {
        case .current: return "Current cats-in-box icon"
        case .original: return ""
        case .shinobi: return "Hidden village cats"
        case .electricPulse: return "Charged alternate icon"
        case .oceanConnect: return "Blue current icon"
        case .devinePurple: return "Purple energy icon"
        case .greenTerminal: return ""
        case .cosmicForum: return ""
        case .crystalFrost: return ""
        case .cyberDistrict: return ""
        case .midnightAMOLED: return ""
        case .rgbArena: return ""
        case .neuralCore: return ""
        }
    }

    var assetName: String {
        switch self {
        case .current: return "app_icon_current"
        case .original: return "app_icon_original"
        case .shinobi: return "app_icon_shinobi"
        case .electricPulse: return "app_icon_electric_pulse"
        case .oceanConnect: return "app_icon_ocean_connect"
        case .devinePurple: return "app_icon_devine_purple"
        case .greenTerminal: return "app_icon_green_terminal"
        case .cosmicForum: return "app_icon_cosmic_forum"
        case .crystalFrost: return "app_icon_crystal_frost"
        case .cyberDistrict: return "app_icon_cyber_district"
        case .midnightAMOLED: return "app_icon_midnight_amoled"
        case .rgbArena: return "app_icon_rgb_arena"
        case .neuralCore: return "app_icon_neural_core"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .current: return nil
        case .original: return "AppIconOriginal"
        case .shinobi: return "AppIconShinobi"
        case .electricPulse: return "AppIconElectricPulse"
        case .oceanConnect: return "AppIconOceanConnect"
        case .devinePurple: return "AppIconDevinePurple"
        case .greenTerminal: return "AppIconGreenTerminal"
        case .cosmicForum: return "AppIconCosmicForum"
        case .crystalFrost: return "AppIconCrystalFrost"
        case .cyberDistrict: return "AppIconCyberDistrict"
        case .midnightAMOLED: return "AppIconMidnightAMOLED"
        case .rgbArena: return "AppIconRGBArena"
        case .neuralCore: return "AppIconNeuralCore"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .current: return false
        case .original, .shinobi, .electricPulse, .oceanConnect, .devinePurple, .greenTerminal, .cosmicForum, .crystalFrost, .cyberDistrict, .midnightAMOLED, .rgbArena, .neuralCore: return true
        }
    }

    var showsProBadge: Bool {
        switch self {
        case .current, .original: return false
        case .shinobi, .electricPulse, .oceanConnect, .devinePurple, .greenTerminal, .cosmicForum, .crystalFrost, .cyberDistrict, .midnightAMOLED, .rgbArena, .neuralCore: return true
        }
    }

    static var supportsAlternateIcons: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        !isRunningInLiveContainer && UIApplication.shared.supportsAlternateIcons
        #else
        false
        #endif
    }

    static var isRunningInLiveContainer: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let pathHints = [
            Bundle.main.bundlePath,
            Bundle.main.executablePath ?? "",
            NSHomeDirectory()
        ]
        if pathHints.contains(where: { $0.localizedCaseInsensitiveContains("LiveContainer") }) {
            return true
        }

        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index) else { continue }
            let name = String(cString: imageName)
            if name.localizedCaseInsensitiveContains("LiveContainer") ||
                name.localizedCaseInsensitiveContains("TweakLoader.dylib") {
                return true
            }
        }
        return false
        #else
        false
        #endif
    }

    static var liveContainerUnsupportedMessage: String {
        "LiveContainer does not allow guest apps to change the installed Home Screen icon. Install Alley Cãt directly with SideStore, AltStore, or TestFlight to use icon switching."
    }

    static func message(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain && nsError.code == -54 {
            return liveContainerUnsupportedMessage
        }
        return error.localizedDescription
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
