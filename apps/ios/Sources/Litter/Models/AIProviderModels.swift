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

    var fileURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(storageFileName ?? fileName)
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}
