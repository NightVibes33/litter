import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case appleOnDevice
    case openAI
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple On-Device"
        case .openAI: return "OpenAI"
        case .openAICompatible: return "OpenAI-Compatible Server"
        }
    }
}

struct AIProviderCapabilities: Codable, Equatable {
    var supportsModelsEndpoint: Bool
    var supportsChatCompletions: Bool
    var supportsStreaming: Bool
    var requiresNetwork: Bool

    static let appleOnDevice = AIProviderCapabilities(
        supportsModelsEndpoint: false,
        supportsChatCompletions: true,
        supportsStreaming: true,
        requiresNetwork: false
    )

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
        guard capabilities.requiresNetwork else { return nil }
        return AIProviderProfile.normalizedBaseURL(baseURL)
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

    static func appleOnDevice() -> AIProviderProfile {
        let now = Date()
        return AIProviderProfile(
            id: UUID(uuidString: "A11E0000-0000-4000-8000-000000000001")!,
            kind: .appleOnDevice,
            displayName: "Apple On-Device",
            baseURL: "",
            defaultModel: "system-language-model",
            isEnabled: true,
            capabilities: .appleOnDevice,
            createdAt: now,
            updatedAt: now
        )
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
        case .healthy: return models.isEmpty ? "Ready" : "Ready · \(models.count) models"
        case .warning(let message): return message
        case .failed(let message): return message
        }
    }
}

enum AIModelRoutingMode: String, CaseIterable, Identifiable {
    case automatic
    case appleOnDevice
    case openAI
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .appleOnDevice: return "Apple On-Device"
        case .openAI: return "OpenAI"
        case .openAICompatible: return "Ollama / OpenAI-Compatible"
        }
    }
}

extension AIModelRoutingMode: Codable {
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case Self.appleOnDevice.rawValue:
            self = .appleOnDevice
        case Self.openAI.rawValue:
            self = .openAI
        case Self.openAICompatible.rawValue:
            self = .openAICompatible
        default:
            self = .automatic
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct GlobalModelSettings: Codable, Equatable {
    var routingMode: AIModelRoutingMode
    var preferredProviderId: UUID?

    static let defaults = GlobalModelSettings(
        routingMode: .appleOnDevice,
        preferredProviderId: AIProviderProfile.appleOnDevice().id
    )
}
