import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAI
    case openAICompatible
    case localGGUF

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .openAICompatible: return "OpenAI-Compatible Server"
        case .localGGUF: return "On-Device GGUF"
        }
    }
}

struct AIProviderCapabilities: Codable, Equatable {
    var supportsModelsEndpoint: Bool
    var supportsChatCompletions: Bool
    var supportsStreaming: Bool
    var requiresNetwork: Bool

    static let openAI = AIProviderCapabilities(
        supportsModelsEndpoint: true,
        supportsChatCompletions: true,
        supportsStreaming: true,
        requiresNetwork: true
    )

    static let openAICompatible = AIProviderCapabilities(
        supportsModelsEndpoint: true,
        supportsChatCompletions: true,
        supportsStreaming: true,
        requiresNetwork: true
    )

    static let localGGUF = AIProviderCapabilities(
        supportsModelsEndpoint: false,
        supportsChatCompletions: true,
        supportsStreaming: true,
        requiresNetwork: false
    )
}

struct AIProviderProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: AIProviderKind
    var displayName: String
    var baseURL: String
    var defaultModel: String
    var isEnabled: Bool
    var capabilities: AIProviderCapabilities
    var createdAt: Date
    var updatedAt: Date

    var normalizedBaseURL: URL? {
        AIProviderProfile.normalizedBaseURL(baseURL)
    }

    static func normalizedBaseURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value.hasSuffix("/v1") {
            return URL(string: value)
        }
        return URL(string: value + "/v1")
    }

    static func openAI(defaultModel: String = "gpt-4.1") -> AIProviderProfile {
        let now = Date()
        return AIProviderProfile(
            id: UUID(),
            kind: .openAI,
            displayName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            defaultModel: defaultModel,
            isEnabled: true,
            capabilities: .openAI,
            createdAt: now,
            updatedAt: now
        )
    }

    static func ollama(name: String, baseURL: String, defaultModel: String) -> AIProviderProfile {
        let now = Date()
        return AIProviderProfile(
            id: UUID(),
            kind: .openAICompatible,
            displayName: name,
            baseURL: baseURL,
            defaultModel: defaultModel,
            isEnabled: true,
            capabilities: .openAICompatible,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct AIProviderModel: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var providerId: UUID
    var providerKind: AIProviderKind
}

struct AIProviderHealthReport: Equatable {
    enum Status: Equatable {
        case unknown
        case healthy
        case warning(String)
        case failed(String)
    }

    var status: Status
    var models: [String]

    var summary: String {
        switch status {
        case .unknown: return "Not tested"
        case .healthy: return models.isEmpty ? "Reachable" : "Reachable · \(models.count) models"
        case .warning(let message): return message
        case .failed(let message): return message
        }
    }
}

enum LocalModelSafety: String, Codable, CaseIterable {
    case recommended
    case heavy
    case notRecommended
    case pcRecommended

    var displayName: String {
        switch self {
        case .recommended: return "Recommended"
        case .heavy: return "Works but heavy"
        case .notRecommended: return "Not recommended"
        case .pcRecommended: return "Use PC-hosted instead"
        }
    }
}



enum AIModelRoutingMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case openAI
    case openAICompatible
    case localGGUF

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .openAI: return "OpenAI"
        case .openAICompatible: return "Ollama / OpenAI-Compatible"
        case .localGGUF: return "On-Device GGUF"
        }
    }
}

enum LocalModelToolUseMode: String, Codable, CaseIterable, Identifiable {
    case off
    case readOnly
    case approvalRequired

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .readOnly: return "Read-only tools"
        case .approvalRequired: return "Approve shell/write"
        }
    }
}

enum LocalModelKVCacheMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case f16
    case q8
    case q4
    case turbo3
    case turbo4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .f16: return "F16"
        case .q8: return "Q8"
        case .q4: return "Q4"
        case .turbo3: return "TurboQuant 3-bit"
        case .turbo4: return "TurboQuant 4-bit"
        }
    }

    var requiresTurboQuant: Bool {
        switch self {
        case .turbo3, .turbo4: return true
        default: return false
        }
    }
}

enum LocalModelPromptTemplateMode: String, Codable, CaseIterable, Identifiable {
    case litter
    case modelDefault

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .litter: return "Litter template"
        case .modelDefault: return "Model chat template"
        }
    }
}

enum LocalModelFlashAttentionMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case disabled
    case enabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .disabled: return "Disabled"
        case .enabled: return "Enabled"
        }
    }
}

enum LocalModelRopeScalingMode: String, Codable, CaseIterable, Identifiable {
    case modelDefault
    case none
    case linear
    case yarn
    case longrope

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modelDefault: return "Model default"
        case .none: return "None"
        case .linear: return "Linear"
        case .yarn: return "YaRN"
        case .longrope: return "LongRoPE"
        }
    }
}

enum LocalModelMirostatMode: String, Codable, CaseIterable, Identifiable {
    case off
    case v1
    case v2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .v1: return "Mirostat 1"
        case .v2: return "Mirostat 2"
        }
    }
}

enum TurboQuantPreference: String, Codable, CaseIterable, Identifiable {
    case disabled
    case autoWhenAvailable
    case forceTurbo3
    case forceTurbo4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .autoWhenAvailable: return "Auto when available"
        case .forceTurbo3: return "Force TurboQuant 3-bit"
        case .forceTurbo4: return "Force TurboQuant 4-bit"
        }
    }
}

enum TurboQuantAvailability: Codable, Equatable {
    case unavailable(String)
    case available([LocalModelKVCacheMode])

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .available(let modes):
            let labels = modes.map(\.displayName).joined(separator: ", ")
            return labels.isEmpty ? "TurboQuant runtime available" : "Available: \(labels)"
        case .unavailable(let reason):
            return reason
        }
    }
}

struct GlobalModelSettings: Codable, Equatable {
    var routingMode: AIModelRoutingMode
    var preferredProviderId: UUID?
    var autoValidateDownloads: Bool
    var allowCellularDownloads: Bool
    var autoUnloadAfterIdle: Bool
    var warnOnThermalPressure: Bool
    var turboQuantPreference: TurboQuantPreference

    static let defaults = GlobalModelSettings(
        routingMode: .automatic,
        preferredProviderId: nil,
        autoValidateDownloads: true,
        allowCellularDownloads: false,
        autoUnloadAfterIdle: true,
        warnOnThermalPressure: true,
        turboQuantPreference: .autoWhenAvailable
    )
}

struct LocalModelRuntimeSettings: Codable, Equatable {
    var contextTokens: Int
    var maxOutputTokens: Int
    var temperature: Double
    var topP: Double
    var topK: Int
    var minP: Double
    var typicalP: Double
    var dynamicTemperatureRange: Double
    var dynamicTemperatureExponent: Double
    var mirostatMode: LocalModelMirostatMode
    var mirostatTau: Double
    var mirostatEta: Double
    var repeatLastN: Int
    var repeatPenalty: Double
    var frequencyPenalty: Double
    var presencePenalty: Double
    var seed: Int
    var preferredThreadCount: Int
    var batchThreadCount: Int
    var batchSize: Int
    var microBatchSize: Int
    var metalEnabled: Bool
    var gpuLayerCount: Int
    var cpuFallbackAllowed: Bool
    var streamingEnabled: Bool
    var mmapEnabled: Bool
    var mlockEnabled: Bool
    var checkTensors: Bool
    var flashAttentionMode: LocalModelFlashAttentionMode
    var offloadKQV: Bool
    var opOffload: Bool
    var swaFull: Bool
    var kvUnified: Bool
    var toolUseMode: LocalModelToolUseMode
    var maxToolRounds: Int
    var retryAttempts: Int
    var kvCacheMode: LocalModelKVCacheMode
    var promptTemplateMode: LocalModelPromptTemplateMode
    var parseSpecialTokens: Bool
    var stopSequences: [String]
    var ropeScalingMode: LocalModelRopeScalingMode
    var ropeFrequencyBase: Double
    var ropeFrequencyScale: Double
    var yarnExtensionFactor: Double
    var yarnAttentionFactor: Double
    var yarnBetaFast: Double
    var yarnBetaSlow: Double
    var yarnOriginalContext: Int
    var systemPromptOverride: String

    init(
        contextTokens: Int,
        maxOutputTokens: Int,
        temperature: Double,
        topP: Double,
        topK: Int,
        minP: Double = 0,
        typicalP: Double = 1,
        dynamicTemperatureRange: Double = 0,
        dynamicTemperatureExponent: Double = 1,
        mirostatMode: LocalModelMirostatMode = .off,
        mirostatTau: Double = 5,
        mirostatEta: Double = 0.1,
        repeatLastN: Int,
        repeatPenalty: Double,
        frequencyPenalty: Double,
        presencePenalty: Double,
        seed: Int,
        preferredThreadCount: Int,
        batchThreadCount: Int = 0,
        batchSize: Int,
        microBatchSize: Int,
        metalEnabled: Bool,
        gpuLayerCount: Int = -1,
        cpuFallbackAllowed: Bool,
        streamingEnabled: Bool,
        mmapEnabled: Bool = true,
        mlockEnabled: Bool = false,
        checkTensors: Bool = false,
        flashAttentionMode: LocalModelFlashAttentionMode = .automatic,
        offloadKQV: Bool = true,
        opOffload: Bool = true,
        swaFull: Bool = true,
        kvUnified: Bool = false,
        toolUseMode: LocalModelToolUseMode,
        maxToolRounds: Int,
        retryAttempts: Int,
        kvCacheMode: LocalModelKVCacheMode,
        promptTemplateMode: LocalModelPromptTemplateMode = .litter,
        parseSpecialTokens: Bool = true,
        stopSequences: [String] = [],
        ropeScalingMode: LocalModelRopeScalingMode = .modelDefault,
        ropeFrequencyBase: Double = 0,
        ropeFrequencyScale: Double = 0,
        yarnExtensionFactor: Double = -1,
        yarnAttentionFactor: Double = -1,
        yarnBetaFast: Double = -1,
        yarnBetaSlow: Double = -1,
        yarnOriginalContext: Int = 0,
        systemPromptOverride: String
    ) {
        self.contextTokens = contextTokens
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.typicalP = typicalP
        self.dynamicTemperatureRange = dynamicTemperatureRange
        self.dynamicTemperatureExponent = dynamicTemperatureExponent
        self.mirostatMode = mirostatMode
        self.mirostatTau = mirostatTau
        self.mirostatEta = mirostatEta
        self.repeatLastN = repeatLastN
        self.repeatPenalty = repeatPenalty
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.seed = seed
        self.preferredThreadCount = preferredThreadCount
        self.batchThreadCount = batchThreadCount
        self.batchSize = batchSize
        self.microBatchSize = microBatchSize
        self.metalEnabled = metalEnabled
        self.gpuLayerCount = gpuLayerCount
        self.cpuFallbackAllowed = cpuFallbackAllowed
        self.streamingEnabled = streamingEnabled
        self.mmapEnabled = mmapEnabled
        self.mlockEnabled = mlockEnabled
        self.checkTensors = checkTensors
        self.flashAttentionMode = flashAttentionMode
        self.offloadKQV = offloadKQV
        self.opOffload = opOffload
        self.swaFull = swaFull
        self.kvUnified = kvUnified
        self.toolUseMode = toolUseMode
        self.maxToolRounds = maxToolRounds
        self.retryAttempts = retryAttempts
        self.kvCacheMode = kvCacheMode
        self.promptTemplateMode = promptTemplateMode
        self.parseSpecialTokens = parseSpecialTokens
        self.stopSequences = stopSequences
        self.ropeScalingMode = ropeScalingMode
        self.ropeFrequencyBase = ropeFrequencyBase
        self.ropeFrequencyScale = ropeFrequencyScale
        self.yarnExtensionFactor = yarnExtensionFactor
        self.yarnAttentionFactor = yarnAttentionFactor
        self.yarnBetaFast = yarnBetaFast
        self.yarnBetaSlow = yarnBetaSlow
        self.yarnOriginalContext = yarnOriginalContext
        self.systemPromptOverride = systemPromptOverride
    }

    static func defaults(for capability: DeviceCapabilityProfile = .current()) -> LocalModelRuntimeSettings {
        LocalModelRuntimeSettings(
            contextTokens: max(512, capability.recommendedContextTokens),
            maxOutputTokens: 768,
            temperature: 0.2,
            topP: 0.9,
            topK: 40,
            repeatLastN: 64,
            repeatPenalty: 1.08,
            frequencyPenalty: 0,
            presencePenalty: 0,
            seed: -1,
            preferredThreadCount: max(2, min(6, ProcessInfo.processInfo.processorCount)),
            batchSize: 1_024,
            microBatchSize: 512,
            metalEnabled: capability.hasMetal,
            cpuFallbackAllowed: false,
            streamingEnabled: true,
            toolUseMode: .approvalRequired,
            maxToolRounds: 4,
            retryAttempts: 2,
            kvCacheMode: .automatic,
            systemPromptOverride: ""
        )
    }

    func sanitized(for capability: DeviceCapabilityProfile = .current(), turboQuantAvailable: Bool = false) -> LocalModelRuntimeSettings {
        var next = self
        next.contextTokens = min(max(next.contextTokens, 512), 131_072)
        next.maxOutputTokens = min(max(next.maxOutputTokens, 64), 16_384)
        next.temperature = min(max(next.temperature, 0), 2)
        next.topP = min(max(next.topP, 0.05), 1)
        next.topK = min(max(next.topK, 1), 200)
        next.minP = min(max(next.minP, 0), 1)
        next.typicalP = min(max(next.typicalP, 0), 1)
        next.dynamicTemperatureRange = min(max(next.dynamicTemperatureRange, 0), 2)
        next.dynamicTemperatureExponent = min(max(next.dynamicTemperatureExponent, 0.1), 8)
        next.mirostatTau = min(max(next.mirostatTau, 0.1), 20)
        next.mirostatEta = min(max(next.mirostatEta, 0.001), 1)
        next.repeatLastN = min(max(next.repeatLastN, 0), 4_096)
        next.repeatPenalty = min(max(next.repeatPenalty, 0.8), 1.5)
        next.frequencyPenalty = min(max(next.frequencyPenalty, -2), 2)
        next.presencePenalty = min(max(next.presencePenalty, -2), 2)
        next.seed = min(max(next.seed, -1), 4_294_967_295)
        next.preferredThreadCount = min(max(next.preferredThreadCount, 1), max(1, ProcessInfo.processInfo.processorCount))
        next.batchThreadCount = min(max(next.batchThreadCount, 0), max(1, ProcessInfo.processInfo.processorCount))
        next.batchSize = min(max(next.batchSize, 32), 4_096)
        next.microBatchSize = min(max(next.microBatchSize, 32), min(next.batchSize, 2_048))
        next.gpuLayerCount = min(max(next.gpuLayerCount, -1), 512)
        next.maxToolRounds = min(max(next.maxToolRounds, 0), 20)
        next.retryAttempts = min(max(next.retryAttempts, 1), 5)
        let sanitizedStopSequences: [String] = next.stopSequences
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        next.stopSequences = Array(sanitizedStopSequences[..<min(sanitizedStopSequences.count, 12)])
        next.ropeFrequencyBase = min(max(next.ropeFrequencyBase, 0), 1_000_000)
        next.ropeFrequencyScale = min(max(next.ropeFrequencyScale, 0), 100)
        next.yarnExtensionFactor = min(max(next.yarnExtensionFactor, -1), 100)
        next.yarnAttentionFactor = min(max(next.yarnAttentionFactor, -1), 100)
        next.yarnBetaFast = min(max(next.yarnBetaFast, -1), 256)
        next.yarnBetaSlow = min(max(next.yarnBetaSlow, -1), 256)
        next.yarnOriginalContext = min(max(next.yarnOriginalContext, 0), 131_072)
        if !capability.hasMetal {
            next.metalEnabled = false
            next.gpuLayerCount = 0
            next.offloadKQV = false
            next.opOffload = false
        }
        if next.kvCacheMode.requiresTurboQuant, !turboQuantAvailable {
            next.kvCacheMode = .automatic
        }
        return next
    }

    var warningSummary: String? {
        var warnings: [String] = []
        if contextTokens > 16_384 { warnings.append("very high context") }
        if maxOutputTokens > 4_096 { warnings.append("large output budget") }
        if batchSize > 1_024 { warnings.append("large batch") }
        if microBatchSize > 512 { warnings.append("large microbatch") }
        if preferredThreadCount > max(2, ProcessInfo.processInfo.processorCount - 1) { warnings.append("aggressive thread count") }
        if mlockEnabled { warnings.append("memory lock") }
        if ropeScalingMode != .modelDefault { warnings.append("custom RoPE") }
        return warnings.isEmpty ? nil : "Experimental: \(warnings.joined(separator: ", ")). These settings are saved as requested, but may fail or overheat on-device."
    }

    enum CodingKeys: String, CodingKey {
        case contextTokens, maxOutputTokens, temperature, topP, topK, minP, typicalP
        case dynamicTemperatureRange, dynamicTemperatureExponent, mirostatMode, mirostatTau, mirostatEta
        case repeatLastN, repeatPenalty, frequencyPenalty, presencePenalty, seed
        case preferredThreadCount, batchThreadCount, batchSize, microBatchSize
        case metalEnabled, gpuLayerCount, cpuFallbackAllowed, streamingEnabled, mmapEnabled, mlockEnabled, checkTensors
        case flashAttentionMode, offloadKQV, opOffload, swaFull, kvUnified
        case toolUseMode, maxToolRounds, retryAttempts, kvCacheMode
        case promptTemplateMode, parseSpecialTokens, stopSequences
        case ropeScalingMode, ropeFrequencyBase, ropeFrequencyScale, yarnExtensionFactor, yarnAttentionFactor, yarnBetaFast, yarnBetaSlow, yarnOriginalContext
        case systemPromptOverride
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaults()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contextTokens = try container.decodeIfPresent(Int.self, forKey: .contextTokens) ?? defaults.contextTokens
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? defaults.maxOutputTokens
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? defaults.topP
        topK = try container.decodeIfPresent(Int.self, forKey: .topK) ?? defaults.topK
        minP = try container.decodeIfPresent(Double.self, forKey: .minP) ?? defaults.minP
        typicalP = try container.decodeIfPresent(Double.self, forKey: .typicalP) ?? defaults.typicalP
        dynamicTemperatureRange = try container.decodeIfPresent(Double.self, forKey: .dynamicTemperatureRange) ?? defaults.dynamicTemperatureRange
        dynamicTemperatureExponent = try container.decodeIfPresent(Double.self, forKey: .dynamicTemperatureExponent) ?? defaults.dynamicTemperatureExponent
        mirostatMode = try container.decodeIfPresent(LocalModelMirostatMode.self, forKey: .mirostatMode) ?? defaults.mirostatMode
        mirostatTau = try container.decodeIfPresent(Double.self, forKey: .mirostatTau) ?? defaults.mirostatTau
        mirostatEta = try container.decodeIfPresent(Double.self, forKey: .mirostatEta) ?? defaults.mirostatEta
        repeatLastN = try container.decodeIfPresent(Int.self, forKey: .repeatLastN) ?? defaults.repeatLastN
        repeatPenalty = try container.decodeIfPresent(Double.self, forKey: .repeatPenalty) ?? defaults.repeatPenalty
        frequencyPenalty = try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty) ?? defaults.frequencyPenalty
        presencePenalty = try container.decodeIfPresent(Double.self, forKey: .presencePenalty) ?? defaults.presencePenalty
        seed = try container.decodeIfPresent(Int.self, forKey: .seed) ?? defaults.seed
        preferredThreadCount = try container.decodeIfPresent(Int.self, forKey: .preferredThreadCount) ?? defaults.preferredThreadCount
        batchThreadCount = try container.decodeIfPresent(Int.self, forKey: .batchThreadCount) ?? defaults.batchThreadCount
        batchSize = try container.decodeIfPresent(Int.self, forKey: .batchSize) ?? defaults.batchSize
        microBatchSize = try container.decodeIfPresent(Int.self, forKey: .microBatchSize) ?? defaults.microBatchSize
        metalEnabled = try container.decodeIfPresent(Bool.self, forKey: .metalEnabled) ?? defaults.metalEnabled
        gpuLayerCount = try container.decodeIfPresent(Int.self, forKey: .gpuLayerCount) ?? defaults.gpuLayerCount
        cpuFallbackAllowed = try container.decodeIfPresent(Bool.self, forKey: .cpuFallbackAllowed) ?? defaults.cpuFallbackAllowed
        streamingEnabled = try container.decodeIfPresent(Bool.self, forKey: .streamingEnabled) ?? defaults.streamingEnabled
        mmapEnabled = try container.decodeIfPresent(Bool.self, forKey: .mmapEnabled) ?? defaults.mmapEnabled
        mlockEnabled = try container.decodeIfPresent(Bool.self, forKey: .mlockEnabled) ?? defaults.mlockEnabled
        checkTensors = try container.decodeIfPresent(Bool.self, forKey: .checkTensors) ?? defaults.checkTensors
        flashAttentionMode = try container.decodeIfPresent(LocalModelFlashAttentionMode.self, forKey: .flashAttentionMode) ?? defaults.flashAttentionMode
        offloadKQV = try container.decodeIfPresent(Bool.self, forKey: .offloadKQV) ?? defaults.offloadKQV
        opOffload = try container.decodeIfPresent(Bool.self, forKey: .opOffload) ?? defaults.opOffload
        swaFull = try container.decodeIfPresent(Bool.self, forKey: .swaFull) ?? defaults.swaFull
        kvUnified = try container.decodeIfPresent(Bool.self, forKey: .kvUnified) ?? defaults.kvUnified
        toolUseMode = try container.decodeIfPresent(LocalModelToolUseMode.self, forKey: .toolUseMode) ?? defaults.toolUseMode
        maxToolRounds = try container.decodeIfPresent(Int.self, forKey: .maxToolRounds) ?? defaults.maxToolRounds
        retryAttempts = try container.decodeIfPresent(Int.self, forKey: .retryAttempts) ?? defaults.retryAttempts
        kvCacheMode = try container.decodeIfPresent(LocalModelKVCacheMode.self, forKey: .kvCacheMode) ?? defaults.kvCacheMode
        promptTemplateMode = try container.decodeIfPresent(LocalModelPromptTemplateMode.self, forKey: .promptTemplateMode) ?? defaults.promptTemplateMode
        parseSpecialTokens = try container.decodeIfPresent(Bool.self, forKey: .parseSpecialTokens) ?? defaults.parseSpecialTokens
        stopSequences = try container.decodeIfPresent([String].self, forKey: .stopSequences) ?? defaults.stopSequences
        ropeScalingMode = try container.decodeIfPresent(LocalModelRopeScalingMode.self, forKey: .ropeScalingMode) ?? defaults.ropeScalingMode
        ropeFrequencyBase = try container.decodeIfPresent(Double.self, forKey: .ropeFrequencyBase) ?? defaults.ropeFrequencyBase
        ropeFrequencyScale = try container.decodeIfPresent(Double.self, forKey: .ropeFrequencyScale) ?? defaults.ropeFrequencyScale
        yarnExtensionFactor = try container.decodeIfPresent(Double.self, forKey: .yarnExtensionFactor) ?? defaults.yarnExtensionFactor
        yarnAttentionFactor = try container.decodeIfPresent(Double.self, forKey: .yarnAttentionFactor) ?? defaults.yarnAttentionFactor
        yarnBetaFast = try container.decodeIfPresent(Double.self, forKey: .yarnBetaFast) ?? defaults.yarnBetaFast
        yarnBetaSlow = try container.decodeIfPresent(Double.self, forKey: .yarnBetaSlow) ?? defaults.yarnBetaSlow
        yarnOriginalContext = try container.decodeIfPresent(Int.self, forKey: .yarnOriginalContext) ?? defaults.yarnOriginalContext
        systemPromptOverride = try container.decodeIfPresent(String.self, forKey: .systemPromptOverride) ?? defaults.systemPromptOverride
    }
}

enum LocalModelValidationStatus: Codable, Equatable {
    case untested
    case validating
    case verified(Date)
    case failed(String, Date)

    var displayName: String {
        switch self {
        case .untested: return "Not verified"
        case .validating: return "Verifying"
        case .verified: return "Verified runnable"
        case .failed: return "Failed validation"
        }
    }

    var message: String {
        switch self {
        case .untested: return "Run a smoke test before relying on this model."
        case .validating: return "Loading model and generating a short test response."
        case .verified(let date): return "Last verified \(date.formatted(date: .abbreviated, time: .shortened))."
        case .failed(let reason, _): return reason
        }
    }
}

enum LocalModelModality: String, Codable, CaseIterable, Identifiable {
    case text
    case image
    case audio
    case video

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Images"
        case .audio: return "Audio"
        case .video: return "Video frames"
        }
    }
}

struct LocalModelRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var storageFileName: String?
    var fileSizeBytes: Int64
    var parameterHint: Double?
    var quantizationHint: String?
    var importedAt: Date
    var safety: LocalModelSafety
    var recommendation: String
    var sourceRepository: String?
    var sourceURL: String?
    var architecture: String?
    var nativeContextLength: Int?
    var modalities: [LocalModelModality]
    var projectorStorageFileName: String?
    var sha256: String?
    var downloadedAt: Date?
    var validationStatus: LocalModelValidationStatus
    var codexEvalScore: Int?
    var codexEvalSummary: String?
    var codexEvalDate: Date?

    init(
        id: UUID,
        fileName: String,
        storageFileName: String?,
        fileSizeBytes: Int64,
        parameterHint: Double?,
        quantizationHint: String?,
        importedAt: Date,
        safety: LocalModelSafety,
        recommendation: String,
        sourceRepository: String? = nil,
        sourceURL: String? = nil,
        architecture: String? = nil,
        nativeContextLength: Int? = nil,
        modalities: [LocalModelModality] = [.text],
        projectorStorageFileName: String? = nil,
        sha256: String? = nil,
        downloadedAt: Date? = nil,
        validationStatus: LocalModelValidationStatus = .untested,
        codexEvalScore: Int? = nil,
        codexEvalSummary: String? = nil,
        codexEvalDate: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.storageFileName = storageFileName
        self.fileSizeBytes = fileSizeBytes
        self.parameterHint = parameterHint
        self.quantizationHint = quantizationHint
        self.importedAt = importedAt
        self.safety = safety
        self.recommendation = recommendation
        self.sourceRepository = sourceRepository
        self.sourceURL = sourceURL
        self.architecture = architecture
        self.nativeContextLength = nativeContextLength
        self.modalities = modalities.isEmpty ? [.text] : modalities
        self.projectorStorageFileName = projectorStorageFileName
        self.sha256 = sha256
        self.downloadedAt = downloadedAt
        self.validationStatus = validationStatus
        self.codexEvalScore = codexEvalScore
        self.codexEvalSummary = codexEvalSummary
        self.codexEvalDate = codexEvalDate
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, storageFileName, fileSizeBytes, parameterHint, quantizationHint, importedAt, safety, recommendation
        case sourceRepository, sourceURL, architecture, nativeContextLength, modalities, projectorStorageFileName, sha256, downloadedAt, validationStatus
        case codexEvalScore, codexEvalSummary, codexEvalDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        storageFileName = try container.decodeIfPresent(String.self, forKey: .storageFileName)
        fileSizeBytes = try container.decode(Int64.self, forKey: .fileSizeBytes)
        parameterHint = try container.decodeIfPresent(Double.self, forKey: .parameterHint)
        quantizationHint = try container.decodeIfPresent(String.self, forKey: .quantizationHint)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        safety = try container.decode(LocalModelSafety.self, forKey: .safety)
        recommendation = try container.decode(String.self, forKey: .recommendation)
        sourceRepository = try container.decodeIfPresent(String.self, forKey: .sourceRepository)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        architecture = try container.decodeIfPresent(String.self, forKey: .architecture)
        nativeContextLength = try container.decodeIfPresent(Int.self, forKey: .nativeContextLength)
        modalities = try container.decodeIfPresent([LocalModelModality].self, forKey: .modalities) ?? [.text]
        projectorStorageFileName = try container.decodeIfPresent(String.self, forKey: .projectorStorageFileName)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt)
        validationStatus = try container.decodeIfPresent(LocalModelValidationStatus.self, forKey: .validationStatus) ?? .untested
        codexEvalScore = try container.decodeIfPresent(Int.self, forKey: .codexEvalScore)
        codexEvalSummary = try container.decodeIfPresent(String.self, forKey: .codexEvalSummary)
        codexEvalDate = try container.decodeIfPresent(Date.self, forKey: .codexEvalDate)
    }

    var fileURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(storageFileName ?? fileName)
    }

    var projectorURL: URL? {
        guard let projectorStorageFileName else { return nil }
        return URL.documentsDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(projectorStorageFileName)
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var supportsMultimodalInput: Bool {
        modalities.contains(.image) || modalities.contains(.audio) || modalities.contains(.video)
    }

    var canRunLocally: Bool {
        if case .verified = validationStatus { return true }
        return false
    }

    var localSelectionId: String {
        "local-gguf:\(id.uuidString)"
    }

    var canRunCodexStyle: Bool {
        canRunLocally && (codexEvalScore ?? 0) >= 70
    }

    var codexReadinessSummary: String {
        guard let codexEvalScore else {
            return canRunLocally
                ? "Runnable, but Codex-style tool quality has not been scored yet."
                : "Validate the model before enabling it for Codex-style conversations."
        }
        let summary = codexEvalSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = summary?.isEmpty == false ? summary! : "Codex-style eval completed."
        return "\(codexEvalScore)/100 - \(label)"
    }
}

struct LocalModelCatalogItem: Identifiable, Equatable {
    var id: String
    var repository: String
    var title: String
    var subtitle: String
    var recommendedFileName: String
    var projectorFileName: String?
    var architecture: String
    var modalities: [LocalModelModality]
    var sizeBytes: Int64
    var warning: String?

    var downloadURL: URL? {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(recommendedFileName)")
    }

    var projectorDownloadURL: URL? {
        guard let projectorFileName else { return nil }
        return URL(string: "https://huggingface.co/\(repository)/resolve/main/\(projectorFileName)")
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static let recommended: [LocalModelCatalogItem] = [
        LocalModelCatalogItem(
            id: "gemma-4-e2b-it-q8",
            repository: "ggml-org/gemma-4-E2B-it-GGUF",
            title: "Gemma 4 E2B IT",
            subtitle: "Best Gemma 4 starting point for iPhone",
            recommendedFileName: "gemma-4-E2B-it-Q8_0.gguf",
            projectorFileName: "mmproj-gemma-4-E2B-it-Q8_0.gguf",
            architecture: "gemma4",
            modalities: [.text, .image, .audio, .video],
            sizeBytes: 4_967_494_592,
            warning: "Requires several GB of free storage and a current high-memory iPhone."
        ),
        LocalModelCatalogItem(
            id: "gemma-4-e4b-it-q4",
            repository: "ggml-org/gemma-4-E4B-it-GGUF",
            title: "Gemma 4 E4B IT",
            subtitle: "Higher quality, heavier iPhone option",
            recommendedFileName: "gemma-4-E4B-it-Q4_K_M.gguf",
            projectorFileName: "mmproj-gemma-4-E4B-it-Q8_0.gguf",
            architecture: "gemma4",
            modalities: [.text, .image, .audio, .video],
            sizeBytes: 5_335_289_824,
            warning: "Large model. Expect heat, slower output, and aggressive storage checks."
        ),
        LocalModelCatalogItem(
            id: "gemma-3-1b-it-q4",
            repository: "ggml-org/gemma-3-1b-it-GGUF",
            title: "Gemma 3 1B IT",
            subtitle: "Small fallback for older devices",
            recommendedFileName: "gemma-3-1b-it-Q4_K_M.gguf",
            projectorFileName: nil,
            architecture: "gemma3",
            modalities: [.text],
            sizeBytes: 806_058_240,
            warning: nil
        )
    ]
}

struct HuggingFaceModelSearchResult: Decodable, Identifiable, Equatable {
    var id: String { modelId }
    let modelId: String
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
}

struct HuggingFaceModelDetails: Decodable, Equatable {
    struct GGUF: Decodable, Equatable {
        let architecture: String?
        let contextLength: Int?

        enum CodingKeys: String, CodingKey {
            case architecture
            case contextLength = "context_length"
        }
    }

    struct Sibling: Decodable, Equatable, Identifiable {
        struct LFS: Decodable, Equatable {
            let sha256: String?
            let size: Int64?
        }

        var id: String { rfilename }
        let rfilename: String
        let size: Int64?
        let lfs: LFS?

        var isGGUF: Bool { rfilename.lowercased().hasSuffix(".gguf") }
        var isProjector: Bool { rfilename.lowercased().hasPrefix("mmproj-") }
    }

    let modelId: String
    let downloads: Int?
    let likes: Int?
    let gguf: GGUF?
    let siblings: [Sibling]

    var ggufFiles: [Sibling] {
        siblings.filter { $0.isGGUF && !$0.isProjector }
    }

    var projectorFiles: [Sibling] {
        siblings.filter { $0.isGGUF && $0.isProjector }
    }
}
