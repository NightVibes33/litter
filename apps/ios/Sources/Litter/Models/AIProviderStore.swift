import Combine
import CryptoKit
import Foundation
import Security

@MainActor
final class AIProviderStore: ObservableObject {
    static let shared = AIProviderStore()

    @Published private(set) var providers: [AIProviderProfile] = []
    @Published private(set) var localModels: [LocalModelRecord] = []
    @Published private(set) var localModelDownloadProgress: LocalModelDownloadProgress?
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
    private var activeModelDownload: TrackedModelDownload?

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
        let capabilities = await LocalLlamaRuntime.shared.capabilities()
        turboQuantAvailability = capabilities.turboQuant
        if !capabilities.turboQuant.isAvailable {
            sanitizeTurboQuantSettings()
        }
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
            return AIProviderHealthReport(status: .healthy, models: localModels.map(\.fileName))
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

    func importLocalModel(from sourceURL: URL, capability: DeviceCapabilityProfile = .current()) async throws -> LocalModelRecord {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let modelsDir = try localModelsDirectory()
        let destination = try availableLocalModelDestination(
            preferredFileName: sourceURL.lastPathComponent,
            in: modelsDir
        )
        let tempDestination = modelsDir.appendingPathComponent(
            ".\(sourceURL.lastPathComponent).litter-import-\(UUID().uuidString).tmp"
        )
        let size = try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            do {
                if fileManager.fileExists(atPath: tempDestination.path) {
                    try fileManager.removeItem(at: tempDestination)
                }
                try fileManager.copyItem(at: sourceURL, to: tempDestination)
                let attributes = try fileManager.attributesOfItem(atPath: tempDestination.path)
                let copiedSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                if fileManager.fileExists(atPath: destination.path) {
                    throw NSError(
                        domain: "AIProviderStore",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "A local model with that filename already exists."]
                    )
                }
                try fileManager.moveItem(at: tempDestination, to: destination)
                return copiedSize
            } catch {
                try? fileManager.removeItem(at: tempDestination)
                throw error
            }
        }.value

        let fileName = destination.lastPathComponent
        let safety = capability.safety(forFileSize: size, fileName: fileName)
        let record = LocalModelRecord(
            id: UUID(),
            fileName: fileName,
            storageFileName: fileName,
            fileSizeBytes: size,
            parameterHint: DeviceCapabilityProfile.parameterHint(from: fileName.lowercased()),
            quantizationHint: DeviceCapabilityProfile.quantizationHint(from: fileName.lowercased()),
            importedAt: Date(),
            safety: safety.0,
            recommendation: safety.1,
            modalities: [.text]
        )
        localModels.removeAll { ($0.storageFileName ?? $0.fileName) == fileName }
        localModels.append(record)
        try persistLocalModels()
        ensureLocalProviderExists()
        if globalModelSettings.autoValidateDownloads {
            Task { await validateLocalModel(record) }
        }
        return record
    }

    func searchHuggingFaceModels(query: String) async throws -> [HuggingFaceModelSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: trimmed),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "filter", value: "gguf")
        ]
        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        return try JSONDecoder().decode([HuggingFaceModelSearchResult].self, from: data)
            .filter { ($0.tags ?? []).contains("gguf") || $0.modelId.lowercased().contains("gguf") }
    }

    func fetchHuggingFaceModelDetails(repository: String) async throws -> HuggingFaceModelDetails {
        let cleaned = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw NSError(domain: "AIProviderStore", code: 20, userInfo: [NSLocalizedDescriptionKey: "Missing model repository."])
        }
        guard let url = URL(string: "https://huggingface.co/api/models/\(cleaned)?blobs=true") else {
            throw NSError(domain: "AIProviderStore", code: 21, userInfo: [NSLocalizedDescriptionKey: "Invalid model repository."])
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        return try JSONDecoder().decode(HuggingFaceModelDetails.self, from: data)
    }

    func downloadCatalogModel(_ item: LocalModelCatalogItem, capability: DeviceCapabilityProfile = .current()) async throws -> LocalModelRecord {
        guard let url = item.downloadURL else {
            throw NSError(domain: "AIProviderStore", code: 30, userInfo: [NSLocalizedDescriptionKey: "Invalid model download URL."])
        }
        let projector: DownloadedModelFile?
        if let projectorURL = item.projectorDownloadURL, let projectorFileName = item.projectorFileName {
            projector = try await downloadModelFile(url: projectorURL, fileName: projectorFileName)
        } else {
            projector = nil
        }
        let model = try await downloadModelFile(url: url, fileName: item.recommendedFileName)
        return try await storeDownloadedModel(
            model,
            projector: projector,
            sourceRepository: item.repository,
            architecture: item.architecture,
            modalities: item.modalities,
            capability: capability
        )
    }

    func downloadHuggingFaceFile(
        repository: String,
        file: HuggingFaceModelDetails.Sibling,
        projector: HuggingFaceModelDetails.Sibling?,
        architecture: String?,
        capability: DeviceCapabilityProfile = .current()
    ) async throws -> LocalModelRecord {
        guard let url = URL(string: "https://huggingface.co/\(repository)/resolve/main/\(file.rfilename)") else {
            throw NSError(domain: "AIProviderStore", code: 31, userInfo: [NSLocalizedDescriptionKey: "Invalid model file URL."])
        }
        let projectorDownload: DownloadedModelFile?
        if let projector, let projectorURL = URL(string: "https://huggingface.co/\(repository)/resolve/main/\(projector.rfilename)") {
            projectorDownload = try await downloadModelFile(url: projectorURL, fileName: projector.rfilename, expectedSHA256: projector.lfs?.sha256)
        } else {
            projectorDownload = nil
        }
        let model = try await downloadModelFile(url: url, fileName: file.rfilename, expectedSHA256: file.lfs?.sha256)
        return try await storeDownloadedModel(
            model,
            projector: projectorDownload,
            sourceRepository: repository,
            architecture: architecture,
            modalities: modalities(forArchitecture: architecture, hasProjector: projectorDownload != nil),
            capability: capability
        )
    }

    func cancelLocalModelDownload() {
        activeModelDownload?.cancel()
        localModelDownloadProgress = localModelDownloadProgress?.cancelledCopy()
    }

    func downloadCustomModel(url: URL, capability: DeviceCapabilityProfile = .current()) async throws -> LocalModelRecord {
        guard url.pathExtension.lowercased() == "gguf" else {
            throw NSError(domain: "AIProviderStore", code: 32, userInfo: [NSLocalizedDescriptionKey: "Only direct .gguf URLs are supported."])
        }
        let model = try await downloadModelFile(url: url, fileName: url.lastPathComponent)
        return try await storeDownloadedModel(
            model,
            projector: nil,
            sourceRepository: nil,
            architecture: nil,
            modalities: [.text],
            capability: capability
        )
    }

    func validateLocalModel(_ record: LocalModelRecord) async {
        guard let index = localModels.firstIndex(where: { $0.id == record.id }) else { return }
        validatingLocalModelId = record.id
        localModels[index].validationStatus = .validating
        try? persistLocalModels()
        do {
            _ = try await LocalLlamaRuntime.shared.smokeTest(localModels[index])
            if let currentIndex = localModels.firstIndex(where: { $0.id == record.id }) {
                localModels[currentIndex].validationStatus = .verified(Date())
                try? persistLocalModels()
            }
        } catch {
            if let currentIndex = localModels.firstIndex(where: { $0.id == record.id }) {
                localModels[currentIndex].validationStatus = .failed(error.localizedDescription, Date())
                try? persistLocalModels()
            }
        }
        if validatingLocalModelId == record.id {
            validatingLocalModelId = nil
        }
    }

    func cancelLocalModelValidation() {
        Task { await LocalLlamaRuntime.shared.cancel() }
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

    private func storeDownloadedModel(
        _ model: DownloadedModelFile,
        projector: DownloadedModelFile?,
        sourceRepository: String?,
        architecture: String?,
        modalities: [LocalModelModality],
        capability: DeviceCapabilityProfile
    ) async throws -> LocalModelRecord {
        let modelsDir = try localModelsDirectory()
        let destination = try availableLocalModelDestination(preferredFileName: model.fileName, in: modelsDir)
        let projectorDestination = try projector.map { try availableLocalModelDestination(preferredFileName: $0.fileName, in: modelsDir) }
        let requiredBytes = model.sizeBytes + (projector?.sizeBytes ?? 0) + 2_000_000_000
        guard capability.freeDiskBytes > requiredBytes else {
            throw NSError(domain: "AIProviderStore", code: 33, userInfo: [NSLocalizedDescriptionKey: "Not enough free storage for this model and runtime cache."])
        }
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try fileManager.moveItem(at: model.temporaryURL, to: destination)
            if let projector, let projectorDestination {
                try fileManager.moveItem(at: projector.temporaryURL, to: projectorDestination)
            }
        }.value

        let fileName = destination.lastPathComponent
        let safety = capability.safety(forFileSize: model.sizeBytes, fileName: fileName)
        let record = LocalModelRecord(
            id: UUID(),
            fileName: fileName,
            storageFileName: fileName,
            fileSizeBytes: model.sizeBytes,
            parameterHint: DeviceCapabilityProfile.parameterHint(from: fileName.lowercased()),
            quantizationHint: DeviceCapabilityProfile.quantizationHint(from: fileName.lowercased()),
            importedAt: Date(),
            safety: safety.0,
            recommendation: safety.1,
            sourceRepository: sourceRepository,
            sourceURL: model.sourceURL.absoluteString,
            architecture: architecture,
            modalities: modalities,
            projectorStorageFileName: projectorDestination?.lastPathComponent,
            sha256: model.sha256,
            downloadedAt: Date()
        )
        localModels.removeAll { ($0.storageFileName ?? $0.fileName) == fileName }
        localModels.append(record)
        try persistLocalModels()
        ensureLocalProviderExists()
        if globalModelSettings.autoValidateDownloads {
            Task { await validateLocalModel(record) }
        }
        return record
    }

    private func downloadModelFile(url: URL, fileName: String, expectedSHA256: String? = nil) async throws -> DownloadedModelFile {
        let download = TrackedModelDownload(url: url, fileName: fileName)
        activeModelDownload = download
        localModelDownloadProgress = .starting(fileName: fileName, sourceURL: url)
        defer {
            activeModelDownload = nil
            if let progress = localModelDownloadProgress, progress.phase == .finished || !progress.isFinished {
                localModelDownloadProgress = nil
            }
        }

        do {
            let (temporaryURL, response) = try await download.start { [weak self] progress in
                Task { @MainActor in
                    self?.localModelDownloadProgress = progress
                }
            }
            try validate(response)
            localModelDownloadProgress = localModelDownloadProgress?.verifyingCopy()
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let actualSHA = try sha256(of: temporaryURL)
            if let expectedSHA256, !expectedSHA256.isEmpty, actualSHA.lowercased() != expectedSHA256.lowercased() {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw NSError(domain: "AIProviderStore", code: 34, userInfo: [NSLocalizedDescriptionKey: "Downloaded file checksum did not match."])
            }
            localModelDownloadProgress = localModelDownloadProgress?.finishedCopy()
            return DownloadedModelFile(
                temporaryURL: temporaryURL,
                sourceURL: url,
                fileName: fileName,
                sizeBytes: size,
                sha256: actualSHA
            )
        } catch {
            localModelDownloadProgress = error is CancellationError ? localModelDownloadProgress?.cancelledCopy() : localModelDownloadProgress?.failedCopy(error.localizedDescription)
            throw error
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func modalities(forArchitecture architecture: String?, hasProjector: Bool) -> [LocalModelModality] {
        guard hasProjector else { return [.text] }
        if architecture?.lowercased() == "gemma4" {
            return [.text, .image, .audio, .video]
        }
        return [.text, .image]
    }

    private func availableLocalModelDestination(preferredFileName: String, in directory: URL) throws -> URL {
        let fallback = "model.gguf"
        let cleaned = preferredFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = cleaned.isEmpty ? fallback : cleaned
        let nsName = fileName as NSString
        let stem = nsName.deletingPathExtension.isEmpty ? fileName : nsName.deletingPathExtension
        let ext = nsName.pathExtension
        let existingStorageNames = Set(localModels.map { ($0.storageFileName ?? $0.fileName).lowercased() })

        for index in 0..<100 {
            let candidate: String
            if index == 0 {
                candidate = fileName
            } else if ext.isEmpty {
                candidate = "\(stem) \(index + 1)"
            } else {
                candidate = "\(stem) \(index + 1).\(ext)"
            }
            let url = directory.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path), !existingStorageNames.contains(candidate.lowercased()) {
                return url
            }
        }

        throw NSError(
            domain: "AIProviderStore",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not find a free local model filename."]
        )
    }

    private func load() {
        providers = decode([AIProviderProfile].self, key: providersKey) ?? []
        localModels = decode([LocalModelRecord].self, key: localModelsKey) ?? []
        globalModelSettings = decode(GlobalModelSettings.self, key: globalModelSettingsKey) ?? .defaults
        localModelRuntimeSettings = decode([String: LocalModelRuntimeSettings].self, key: localModelRuntimeSettingsKey) ?? [:]
        ensureDefaultOpenAIProvider()
        ensureLocalProviderExists()
        sanitizeTurboQuantSettings()
    }

    private func ensureDefaultOpenAIProvider() {
        guard !providers.contains(where: { $0.kind == .openAI }) else { return }
        providers.insert(.openAI(), at: 0)
        try? persistProviders()
    }

    private func ensureLocalProviderExists() {
        guard !providers.contains(where: { $0.kind == .localGGUF }) else { return }
        let now = Date()
        providers.append(AIProviderProfile(
            id: UUID(),
            kind: .localGGUF,
            displayName: "On-Device Models",
            baseURL: "local://gguf",
            defaultModel: localModels.first?.fileName ?? "",
            isEnabled: true,
            capabilities: .localGGUF,
            createdAt: now,
            updatedAt: now
        ))
        try? persistProviders()
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

private struct DownloadedModelFile {
    var temporaryURL: URL
    var sourceURL: URL
    var fileName: String
    var sizeBytes: Int64
    var sha256: String
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}


struct LocalModelDownloadProgress: Equatable, Identifiable {
    enum Phase: String, Equatable {
        case starting
        case downloading
        case verifying
        case finished
        case cancelled
        case failed
    }

    var id: String
    var fileName: String
    var sourceURL: URL
    var phase: Phase
    var bytesWritten: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double
    var startedAt: Date
    var updatedAt: Date
    var message: String?

    var fractionCompleted: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, max(0, Double(bytesWritten) / Double(totalBytes)))
    }

    var isFinished: Bool { [.finished, .cancelled, .failed].contains(phase) }

    static func starting(fileName: String, sourceURL: URL) -> LocalModelDownloadProgress {
        let now = Date()
        return LocalModelDownloadProgress(
            id: fileName,
            fileName: fileName,
            sourceURL: sourceURL,
            phase: .starting,
            bytesWritten: 0,
            totalBytes: 0,
            bytesPerSecond: 0,
            startedAt: now,
            updatedAt: now,
            message: nil
        )
    }

    func verifyingCopy() -> LocalModelDownloadProgress {
        copy(phase: .verifying, message: "Verifying checksum")
    }

    func finishedCopy() -> LocalModelDownloadProgress {
        copy(phase: .finished, bytesWritten: max(bytesWritten, totalBytes), message: "Download complete")
    }

    func cancelledCopy() -> LocalModelDownloadProgress {
        copy(phase: .cancelled, message: "Download cancelled")
    }

    func failedCopy(_ message: String) -> LocalModelDownloadProgress {
        copy(phase: .failed, message: message)
    }

    private func copy(
        phase: Phase,
        bytesWritten: Int64? = nil,
        totalBytes: Int64? = nil,
        bytesPerSecond: Double? = nil,
        message: String? = nil
    ) -> LocalModelDownloadProgress {
        LocalModelDownloadProgress(
            id: id,
            fileName: fileName,
            sourceURL: sourceURL,
            phase: phase,
            bytesWritten: bytesWritten ?? self.bytesWritten,
            totalBytes: totalBytes ?? self.totalBytes,
            bytesPerSecond: bytesPerSecond ?? self.bytesPerSecond,
            startedAt: startedAt,
            updatedAt: Date(),
            message: message ?? self.message
        )
    }
}

private final class TrackedModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL
    private let fileName: String
    private let startedAt = Date()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var progressHandler: ((LocalModelDownloadProgress) -> Void)?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var movedTemporaryURL: URL?
    private var completionResponse: URLResponse?
    private var didResume = false
    private let lock = NSLock()

    init(url: URL, fileName: String) {
        self.url = url
        self.fileName = fileName
        super.init()
    }

    func start(progress: @escaping (LocalModelDownloadProgress) -> Void) async throws -> (URL, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.progressHandler = progress
                self.continuation = continuation
                lock.unlock()

                let configuration = URLSessionConfiguration.default
                configuration.waitsForConnectivity = true
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 60 * 60 * 6
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: url)
                self.session = session
                self.task = task
                progress(.starting(fileName: fileName, sourceURL: url))
                task.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        progressHandler?(LocalModelDownloadProgress(
            id: fileName,
            fileName: fileName,
            sourceURL: url,
            phase: .downloading,
            bytesWritten: totalBytesWritten,
            totalBytes: total,
            bytesPerSecond: Double(totalBytesWritten) / elapsed,
            startedAt: startedAt,
            updatedAt: Date(),
            message: nil
        ))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("litter-model-")
                .appendingPathExtension(UUID().uuidString)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            movedTemporaryURL = destination
            completionResponse = downloadTask.response
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(error))
            }
            return
        }
        guard let movedTemporaryURL, let response = completionResponse ?? task.response else {
            finish(.failure(NSError(domain: "AIProviderStore", code: 35, userInfo: [NSLocalizedDescriptionKey: "The model download did not produce a file."])))
            return
        }
        finish(.success((movedTemporaryURL, response)))
    }

    private func finish(_ result: Result<(URL, URLResponse), Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        session?.invalidateAndCancel()
        switch result {
        case .success(let value): continuation?.resume(returning: value)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }
}
