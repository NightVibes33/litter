import Combine
import Foundation
import Security

@MainActor
final class AIProviderStore: ObservableObject {
    static let shared = AIProviderStore()
    static let onDeviceAIUnavailableMessage = "On-device AI is disabled in this build. Use ChatGPT or a PC-hosted OpenAI-compatible server such as Ollama or LM Studio."

    @Published private(set) var providers: [AIProviderProfile] = []
    @Published private(set) var localModels: [LocalModelRecord] = []
    @Published private(set) var validatingLocalModelId: UUID?
    @Published private(set) var globalModelSettings: GlobalModelSettings = .defaults
    @Published private(set) var localModelRuntimeSettings: [String: LocalModelRuntimeSettings] = [:]
    @Published private(set) var turboQuantAvailability: TurboQuantAvailability = .unavailable("Runtime capability has not been scanned yet.")

    private let providersKey = "ai-provider-profiles-v1"
    private let localModelsKey = "local-gguf-models-v1"
    private let globalModelSettingsKey = "global-model-settings-v1"
    private let localModelRuntimeSettingsKey = "local-model-runtime-settings-v1"
    private let keychainService = "com.sigkitten.litter.ai-provider-secret"
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
        migrateOpenAIKeyIfNeeded()
    }

    func reload() {
        load()
        Task { await refreshRuntimeCapabilities() }
    }

    func refreshRuntimeCapabilities() async {
        turboQuantAvailability = .unavailable(Self.onDeviceAIUnavailableMessage)
        sanitizeTurboQuantSettings()
    }

    func updateGlobalModelSettings(_ update: (inout GlobalModelSettings) -> Void) {
        var next = globalModelSettings
        update(&next)
        globalModelSettings = next
        try? persistGlobalModelSettings()
        sanitizeTurboQuantSettings()
    }

    func runtimeSettings(for model: LocalModelRecord, capability: DeviceCapabilityProfile = .current()) -> LocalModelRuntimeSettings {
        let stored = localModelRuntimeSettings[model.id.uuidString] ?? .defaults(for: capability)
        return stored.sanitized(for: capability, turboQuantAvailable: turboQuantAvailability.isAvailable)
    }

    func effectiveRuntimeSettings(for model: LocalModelRecord, capability: DeviceCapabilityProfile = .current()) -> LocalModelRuntimeSettings {
        runtimeSettings(for: model, capability: capability)
    }

    func localModelInfos() -> [ModelInfo] { [] }

    func localModel(forSelection selection: String?) -> LocalModelRecord? { nil }

    func preferredLocalModelForMainConversation() -> LocalModelRecord? { nil }

    func updateCodexEval(for model: LocalModelRecord, score: Int, summary: String) {
        guard let index = localModels.firstIndex(where: { $0.id == model.id }) else { return }
        localModels[index].codexEvalScore = min(100, max(0, score))
        localModels[index].codexEvalSummary = summary
        localModels[index].codexEvalDate = Date()
        try? persistLocalModels()
    }

    func updateRuntimeSettings(
        for model: LocalModelRecord,
        capability: DeviceCapabilityProfile = .current(),
        _ update: (inout LocalModelRuntimeSettings) -> Void
    ) {
        var next = runtimeSettings(for: model, capability: capability)
        update(&next)
        localModelRuntimeSettings[model.id.uuidString] = next.sanitized(for: capability, turboQuantAvailable: turboQuantAvailability.isAvailable)
        try? persistLocalModelRuntimeSettings()
    }

    func resetRuntimeSettings(for model: LocalModelRecord) {
        localModelRuntimeSettings.removeValue(forKey: model.id.uuidString)
        try? persistLocalModelRuntimeSettings()
    }

    func upsertProvider(_ provider: AIProviderProfile, apiKey: String?) throws {
        var next = provider
        next.updatedAt = Date()
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = next
        } else {
            providers.append(next)
        }
        if let apiKey {
            try saveSecret(apiKey, providerId: next.id)
        }
        try persistProviders()
    }

    func deleteProvider(_ provider: AIProviderProfile) throws {
        providers.removeAll { $0.id == provider.id }
        try deleteSecret(providerId: provider.id)
        try persistProviders()
    }

    func secret(for provider: AIProviderProfile) -> String? {
        try? loadSecret(providerId: provider.id)
    }

    func testProvider(_ provider: AIProviderProfile, apiKey: String?) async -> AIProviderHealthReport {
        guard provider.kind != .localGGUF else {
            return AIProviderHealthReport(status: .failed(Self.onDeviceAIUnavailableMessage), models: [])
        }
        guard let base = provider.normalizedBaseURL else {
            return AIProviderHealthReport(status: .failed("Invalid base URL"), models: [])
        }

        do {
            let models = try await fetchModels(baseURL: base, apiKey: apiKey ?? secret(for: provider))
            let model = provider.defaultModel.isEmpty ? models.first : provider.defaultModel
            if let model, !model.isEmpty {
                try await testChatCompletion(baseURL: base, apiKey: apiKey ?? secret(for: provider), model: model)
            }
            return AIProviderHealthReport(status: .healthy, models: models)
        } catch {
            return AIProviderHealthReport(status: .failed(error.localizedDescription), models: [])
        }
    }

    func validateLocalModel(_ record: LocalModelRecord) async {
        guard let index = localModels.firstIndex(where: { $0.id == record.id }) else { return }
        localModels[index].validationStatus = .failed(Self.onDeviceAIUnavailableMessage, Date())
        try? persistLocalModels()
    }

    func cancelLocalModelValidation() {
        validatingLocalModelId = nil
    }

    func removeLocalModel(_ record: LocalModelRecord) throws {
        localModels.removeAll { $0.id == record.id }
        localModelRuntimeSettings.removeValue(forKey: record.id.uuidString)
        let fileURL = record.fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        if let projectorURL = record.projectorURL, FileManager.default.fileExists(atPath: projectorURL.path) {
            try FileManager.default.removeItem(at: projectorURL)
        }
        try persistLocalModels()
        try persistLocalModelRuntimeSettings()
    }

    func localModelsDirectory() throws -> URL {
        let url = URL.documentsDirectory.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func load() {
        providers = decode([AIProviderProfile].self, key: providersKey) ?? []
        localModels = decode([LocalModelRecord].self, key: localModelsKey) ?? []
        globalModelSettings = decode(GlobalModelSettings.self, key: globalModelSettingsKey) ?? .defaults
        localModelRuntimeSettings = decode([String: LocalModelRuntimeSettings].self, key: localModelRuntimeSettingsKey) ?? [:]
        ensureDefaultOpenAIProvider()
        removeLocalProviderIfNeeded()
        sanitizeTurboQuantSettings()
    }

    private func ensureDefaultOpenAIProvider() {
        guard !providers.contains(where: { $0.kind == .openAI }) else { return }
        providers.insert(.openAI(), at: 0)
        try? persistProviders()
    }

    private func removeLocalProviderIfNeeded() {
        let originalCount = providers.count
        providers.removeAll { $0.kind == .localGGUF }
        if providers.count != originalCount {
            try? persistProviders()
        }
        var settingsChanged = false
        if globalModelSettings.routingMode == .localGGUF {
            globalModelSettings.routingMode = .automatic
            settingsChanged = true
        }
        if let preferredProviderId = globalModelSettings.preferredProviderId,
           !providers.contains(where: { $0.id == preferredProviderId }) {
            globalModelSettings.preferredProviderId = nil
            settingsChanged = true
        }
        if settingsChanged {
            try? persistGlobalModelSettings()
        }
    }

    private func migrateOpenAIKeyIfNeeded() {
        guard let openAI = providers.first(where: { $0.kind == .openAI }) else { return }
        guard (try? loadSecret(providerId: openAI.id)) == nil else { return }
        guard let key = try? OpenAIApiKeyStore.shared.load(), !key.isEmpty else { return }
        try? saveSecret(key, providerId: openAI.id)
    }

    private func persistProviders() throws {
        let data = try encoder.encode(providers)
        defaults.set(data, forKey: providersKey)
    }

    private func persistLocalModels() throws {
        let data = try encoder.encode(localModels)
        defaults.set(data, forKey: localModelsKey)
    }

    private func persistGlobalModelSettings() throws {
        let data = try encoder.encode(globalModelSettings)
        defaults.set(data, forKey: globalModelSettingsKey)
    }

    private func persistLocalModelRuntimeSettings() throws {
        let data = try encoder.encode(localModelRuntimeSettings)
        defaults.set(data, forKey: localModelRuntimeSettingsKey)
    }

    private func sanitizeTurboQuantSettings() {
        guard !turboQuantAvailability.isAvailable else { return }
        if globalModelSettings.turboQuantPreference == .forceTurbo3 || globalModelSettings.turboQuantPreference == .forceTurbo4 {
            globalModelSettings.turboQuantPreference = .autoWhenAvailable
            try? persistGlobalModelSettings()
        }
        var changed = false
        for (key, settings) in localModelRuntimeSettings where settings.kvCacheMode.requiresTurboQuant {
            var next = settings
            next.kvCacheMode = .automatic
            localModelRuntimeSettings[key] = next
            changed = true
        }
        if changed { try? persistLocalModelRuntimeSettings() }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func fetchModels(baseURL: URL, apiKey: String?) async throws -> [String] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        applyAuth(apiKey, to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    private func testChatCompletion(baseURL: URL, apiKey: String?, model: String) async throws {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(apiKey, to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "Reply with ok."]],
            "stream": false,
            "max_tokens": 8
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func applyAuth(_ apiKey: String?, to request: inout URLRequest) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "AIProviderStore",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"]
            )
        }
    }

    private func saveSecret(_ secret: String, providerId: UUID) throws {
        let data = Data(secret.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query = keychainQuery(providerId: providerId)
        let attrs = query.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw keychainError(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    private func loadSecret(providerId: UUID) throws -> String? {
        let query = keychainQuery(providerId: providerId).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw keychainError(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSecret(providerId: UUID) throws {
        let status = SecItemDelete(keychainQuery(providerId: providerId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    private func keychainQuery(providerId: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: providerId.uuidString
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "Keychain error (\(status))"]
        )
    }
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}
