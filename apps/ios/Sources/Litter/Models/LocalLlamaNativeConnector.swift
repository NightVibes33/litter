import Foundation

/// Registers the native llama.cpp adapter with the Swift local-model runtime.
/// The adapter is intentionally iOS-only because the current project links
/// `llama.xcframework` only into the iOS application target.
enum LocalLlamaNativeConnector {
    static func installIfAvailable() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard LitterLlamaBridge.isAvailable() else { return }
        Task.detached(priority: .utility) {
            let supportedModes = LitterLlamaBridge.supportedKVCacheModes().compactMap { LocalModelKVCacheMode(rawValue: $0) }
            let turboQuant: TurboQuantAvailability = LitterLlamaBridge.supportsTurboQuant()
                ? .available(supportedModes.filter { $0.requiresTurboQuant })
                : .unavailable("This build links standard llama.cpp KV cache support. Rebuild with a TurboQuant-capable llama.cpp fork to enable TurboQuant modes.")
            await LocalLlamaRuntime.shared.configureCapabilities(LocalLlamaRuntimeCapabilities(
                isAvailable: true,
                turboQuant: turboQuant,
                supportedKVCacheModes: supportedModes.isEmpty ? [.automatic, .f16, .q8, .q4] : supportedModes
            ))
            await LocalLlamaRuntime.shared.configureCancellationHandler {
                LitterLlamaBridge.unload()
            }
            await LocalLlamaRuntime.shared.configureTokenGenerator { request, messages, onToken in
                try await Task.detached(priority: .userInitiated) {
                    let objcMessages = messages.map { message in
                        ["role": message.role.rawValue, "text": message.text]
                    }
                    return try LitterLlamaBridge.generate(
                        withModelPath: request.model.fileURL.path,
                        contextTokens: request.options.contextTokens,
                        maxTokens: request.maxTokens,
                        temperature: request.temperature,
                        topP: request.options.topP,
                        topK: request.options.topK,
                        repeatLastN: request.options.repeatLastN,
                        repeatPenalty: request.options.repeatPenalty,
                        frequencyPenalty: request.options.frequencyPenalty,
                        presencePenalty: request.options.presencePenalty,
                        seed: request.options.seed,
                        threadCount: request.options.preferredThreadCount,
                        batchSize: request.options.batchSize,
                        microBatchSize: request.options.microBatchSize,
                        metalEnabled: request.options.metalEnabled,
                        cpuFallbackAllowed: request.options.cpuFallbackAllowed,
                        kvCacheMode: request.options.kvCacheMode.rawValue,
                        messages: objcMessages,
                        onToken: { token in onToken(token) }
                    )
                }.value
            }
        }
        #endif
    }
}
