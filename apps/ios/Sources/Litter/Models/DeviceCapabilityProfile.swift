import Foundation
import Metal
import UIKit

struct DeviceCapabilityProfile: Codable, Equatable {
    enum LocalInferenceTier: String, Codable {
        case unavailable
        case small
        case medium
        case largeWithWarnings

        var displayName: String {
            switch self {
            case .unavailable: return "Unavailable"
            case .small: return "Small local models"
            case .medium: return "Small and medium local models"
            case .largeWithWarnings: return "Large models with warnings"
            }
        }
    }

    var deviceName: String
    var modelIdentifier: String
    var systemVersion: String
    var physicalMemoryBytes: UInt64
    var freeDiskBytes: Int64
    var isLowPowerModeEnabled: Bool
    var thermalState: String
    var hasMetal: Bool
    var metalDeviceName: String?
    var recommendedMaxWorkingSetSize: UInt64?
    var supportedGPUFamilies: [String]
    var localInferenceTier: LocalInferenceTier

    var memoryGB: Double { Double(physicalMemoryBytes) / 1_073_741_824 }
    var freeDiskGB: Double { Double(freeDiskBytes) / 1_073_741_824 }

    var thermalDisplayName: String {
        let lower = thermalState.lowercased()
        if lower.contains("critical") { return "Critical" }
        if lower.contains("serious") { return "Serious" }
        if lower.contains("fair") { return "Fair" }
        if lower.contains("nominal") { return "Nominal" }
        return thermalState.isEmpty ? "Unknown" : thermalState
    }

    var thermalSeverityRank: Int {
        switch thermalDisplayName {
        case "Critical": return 3
        case "Serious": return 2
        case "Fair": return 1
        default: return 0
        }
    }

    var isThermallyConstrained: Bool { thermalSeverityRank >= 2 }

    var modelSafetySummary: String {
        if !hasMetal { return "Local inference will be CPU-only; use Ollama/LM Studio on a PC for serious work." }
        if isThermallyConstrained { return "Thermal pressure is high. Keep context small or unload the model." }
        if isLowPowerModeEnabled { return "Low Power Mode is on. Litter will prefer small local settings." }
        return localGenerationSummary
    }

    var recommendedContextTokens: Int {
        if isLowPowerModeEnabled || thermalState.lowercased().contains("serious") || thermalState.lowercased().contains("critical") {
            return 2_048
        }
        switch localInferenceTier {
        case .unavailable: return 0
        case .small: return 2_048
        case .medium: return 4_096
        case .largeWithWarnings: return 8_192
        }
    }

    var localGenerationSummary: String {
        guard hasMetal else { return "Metal is unavailable; use a PC-hosted OpenAI-compatible Ollama or LM Studio endpoint." }
        let context = recommendedContextTokens > 0 ? "~\(recommendedContextTokens) context tokens" : "no on-device context"
        return "\(localInferenceTier.displayName) · \(String(format: "%.1f", memoryGB)) GB RAM · \(String(format: "%.1f", freeDiskGB)) GB free · \(context)."
    }

    static func current() -> DeviceCapabilityProfile {
        let process = ProcessInfo.processInfo
        let device = UIDevice.current
        let metalDevice = MTLCreateSystemDefaultDevice()
        let freeDisk = availableDiskBytes()
        let gpuFamilies = supportedGPUFamilies(for: metalDevice)
        let tier = inferTier(
            physicalMemoryBytes: process.physicalMemory,
            freeDiskBytes: freeDisk,
            hasMetal: metalDevice != nil,
            thermalState: process.thermalState,
            isLowPowerModeEnabled: process.isLowPowerModeEnabled
        )

        return DeviceCapabilityProfile(
            deviceName: device.name,
            modelIdentifier: hardwareIdentifier(),
            systemVersion: device.systemVersion,
            physicalMemoryBytes: process.physicalMemory,
            freeDiskBytes: freeDisk,
            isLowPowerModeEnabled: process.isLowPowerModeEnabled,
            thermalState: String(describing: process.thermalState),
            hasMetal: metalDevice != nil,
            metalDeviceName: metalDevice?.name,
            recommendedMaxWorkingSetSize: metalDevice?.recommendedMaxWorkingSetSize,
            supportedGPUFamilies: gpuFamilies,
            localInferenceTier: tier
        )
    }

    func safety(forFileSize bytes: Int64, fileName: String) -> (LocalModelSafety, String) {
        let lower = fileName.lowercased()
        let sizeGB = Double(bytes) / 1_073_741_824
        let parameterHint = Self.parameterHint(from: lower)

        guard hasMetal else {
            return (.pcRecommended, "Metal is unavailable, so local inference would be CPU-only and too slow.")
        }
        guard freeDiskBytes > bytes + 2_000_000_000 else {
            return (.notRecommended, "Not enough free storage for the model plus runtime cache.")
        }
        if isLowPowerModeEnabled || thermalState.lowercased().contains("serious") || thermalState.lowercased().contains("critical") {
            return (.heavy, "Device is power or thermally constrained; use low context or a PC-hosted model.")
        }

        switch localInferenceTier {
        case .unavailable:
            return (.pcRecommended, "This device profile is not safe for on-device model inference.")
        case .small:
            if sizeGB <= 3.5 || (parameterHint ?? 99) <= 3.0 {
                return (.recommended, "Good fit for offline command help and lightweight coding tasks.")
            }
            return (.pcRecommended, "This model is likely too heavy for this phone; run it through Ollama on a PC.")
        case .medium:
            if sizeGB <= 5.5 || (parameterHint ?? 99) <= 4.5 {
                return (.recommended, "Safe default for this device with Metal acceleration.")
            }
            if sizeGB <= 8.5 || (parameterHint ?? 99) <= 8.0 {
                return (.heavy, "Should be possible with lower context, but expect heat and battery drain.")
            }
            return (.pcRecommended, "Large local model; use PC-hosted Ollama for better speed and stability.")
        case .largeWithWarnings:
            if sizeGB <= 6.5 || (parameterHint ?? 99) <= 4.5 {
                return (.recommended, "Comfortable on this device class.")
            }
            if sizeGB <= 11 || (parameterHint ?? 99) <= 8.0 {
                return (.heavy, "Possible, but use lower context and monitor temperature.")
            }
            return (.pcRecommended, "Too large for reliable phone use; PC-hosted is the correct path.")
        }
    }

    static func parameterHint(from fileName: String) -> Double? {
        let patterns = ["1b", "2b", "3b", "4b", "7b", "8b", "9b", "12b", "14b", "27b", "70b"]
        for pattern in patterns where fileName.contains(pattern) {
            return Double(pattern.dropLast())
        }
        return nil
    }

    static func quantizationHint(from fileName: String) -> String? {
        let lower = fileName.lowercased()
        for token in ["q2_k", "q3_k", "q4_k_m", "q4_k", "q5_k_m", "q5_k", "q6_k", "q8_0"] where lower.contains(token) {
            return token.uppercased()
        }
        return nil
    }

    private static func inferTier(
        physicalMemoryBytes: UInt64,
        freeDiskBytes: Int64,
        hasMetal: Bool,
        thermalState: ProcessInfo.ThermalState,
        isLowPowerModeEnabled: Bool
    ) -> LocalInferenceTier {
        guard hasMetal, freeDiskBytes > 2_000_000_000 else { return .unavailable }
        if thermalState == .critical { return .unavailable }
        let memoryGB = Double(physicalMemoryBytes) / 1_073_741_824
        if memoryGB >= 10, !isLowPowerModeEnabled, (thermalState == .nominal || thermalState == .fair) {
            return .largeWithWarnings
        }
        if memoryGB >= 7 { return .medium }
        if memoryGB >= 4 { return .small }
        return .unavailable
    }

    private static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, child in
            guard let value = child.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
    }

    private static func availableDiskBytes() -> Int64 {
        let url = URL.documentsDirectory
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let capacity = values?.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return 0
    }

    private static func supportedGPUFamilies(for device: MTLDevice?) -> [String] {
        guard let device else { return [] }
        var families: [String] = []
        if #available(iOS 13.0, *) {
            let candidates: [(MTLGPUFamily, String)] = [
                (.apple1, "Apple1"), (.apple2, "Apple2"), (.apple3, "Apple3"), (.apple4, "Apple4"),
                (.apple5, "Apple5"), (.apple6, "Apple6"), (.apple7, "Apple7"), (.apple8, "Apple8"),
                (.apple9, "Apple9")
            ]
            for (family, name) in candidates where device.supportsFamily(family) {
                families.append(name)
            }
        }
        return families
    }
}
