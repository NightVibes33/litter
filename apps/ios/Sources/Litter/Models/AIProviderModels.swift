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
    var repeatPenalty: Double
    var preferredThreadCount: Int
    var metalEnabled: Bool
    var cpuFallbackAllowed: Bool
    var streamingEnabled: Bool
    var toolUseMode: LocalModelToolUseMode
    var maxToolRounds: Int
    var kvCacheMode: LocalModelKVCacheMode
    var systemPromptOverride: String

    static func defaults(for capability: DeviceCapabilityProfile = .current()) -> LocalModelRuntimeSettings {
        LocalModelRuntimeSettings(
            contextTokens: max(512, capability.recommendedContextTokens),
            maxOutputTokens: 768,
            temperature: 0.2,
            topP: 0.9,
            topK: 40,
            repeatPenalty: 1.08,
            preferredThreadCount: max(2, min(6, ProcessInfo.processInfo.processorCount)),
            metalEnabled: capability.hasMetal,
            cpuFallbackAllowed: false,
            streamingEnabled: true,
            toolUseMode: .approvalRequired,
            maxToolRounds: 4,
            kvCacheMode: .automatic,
            systemPromptOverride: ""
        )
    }

    func sanitized(for capability: DeviceCapabilityProfile = .current(), turboQuantAvailable: Bool = false) -> LocalModelRuntimeSettings {
        var next = self
        let recommended = capability.recommendedContextTokens == 0 ? 2_048 : capability.recommendedContextTokens
        if capability.isThermallyConstrained || capability.isLowPowerModeEnabled {
            next.contextTokens = min(next.contextTokens, 2_048)
            next.maxOutputTokens = min(next.maxOutputTokens, 512)
        } else {
            next.contextTokens = min(max(next.contextTokens, 512), max(2_048, recommended * 2))
            next.maxOutputTokens = min(max(next.maxOutputTokens, 64), 4_096)
        }
        next.temperature = min(max(next.temperature, 0), 2)
        next.topP = min(max(next.topP, 0.05), 1)
        next.topK = min(max(next.topK, 1), 200)
        next.repeatPenalty = min(max(next.repeatPenalty, 0.8), 1.5)
        next.preferredThreadCount = min(max(next.preferredThreadCount, 1), max(1, ProcessInfo.processInfo.processorCount))
        if !capability.hasMetal {
            next.metalEnabled = false
        }
        if next.kvCacheMode.requiresTurboQuant, !turboQuantAvailable {
            next.kvCacheMode = .automatic
        }
        return next
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
    var modalities: [LocalModelModality]
    var projectorStorageFileName: String?
    var sha256: String?
    var downloadedAt: Date?
    var validationStatus: LocalModelValidationStatus

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
        modalities: [LocalModelModality] = [.text],
        projectorStorageFileName: String? = nil,
        sha256: String? = nil,
        downloadedAt: Date? = nil,
        validationStatus: LocalModelValidationStatus = .untested
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
        self.modalities = modalities.isEmpty ? [.text] : modalities
        self.projectorStorageFileName = projectorStorageFileName
        self.sha256 = sha256
        self.downloadedAt = downloadedAt
        self.validationStatus = validationStatus
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, storageFileName, fileSizeBytes, parameterHint, quantizationHint, importedAt, safety, recommendation
        case sourceRepository, sourceURL, architecture, modalities, projectorStorageFileName, sha256, downloadedAt, validationStatus
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
        modalities = try container.decodeIfPresent([LocalModelModality].self, forKey: .modalities) ?? [.text]
        projectorStorageFileName = try container.decodeIfPresent(String.self, forKey: .projectorStorageFileName)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt)
        validationStatus = try container.decodeIfPresent(LocalModelValidationStatus.self, forKey: .validationStatus) ?? .untested
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
