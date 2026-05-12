import XCTest
@testable import Litter

final class LocalModelRuntimeSettingsTests: XCTestCase {
    func testDecodesOlderRuntimeSettingsWithAdvancedDefaults() throws {
        let json = """
        {
          "contextTokens": 4096,
          "maxOutputTokens": 512,
          "temperature": 0.2,
          "topP": 0.9,
          "topK": 40,
          "repeatLastN": 64,
          "repeatPenalty": 1.08,
          "frequencyPenalty": 0,
          "presencePenalty": 0,
          "seed": -1,
          "preferredThreadCount": 4,
          "batchSize": 1024,
          "microBatchSize": 512,
          "metalEnabled": true,
          "cpuFallbackAllowed": false,
          "streamingEnabled": true,
          "toolUseMode": "approvalRequired",
          "maxToolRounds": 4,
          "retryAttempts": 2,
          "kvCacheMode": "automatic",
          "systemPromptOverride": ""
        }
        """

        let settings = try JSONDecoder().decode(LocalModelRuntimeSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.minP, 0)
        XCTAssertEqual(settings.typicalP, 1)
        XCTAssertEqual(settings.dynamicTemperatureRange, 0)
        XCTAssertEqual(settings.mirostatMode, .off)
        XCTAssertEqual(settings.batchThreadCount, 0)
        XCTAssertEqual(settings.gpuLayerCount, -1)
        XCTAssertTrue(settings.mmapEnabled)
        XCTAssertFalse(settings.mlockEnabled)
        XCTAssertEqual(settings.flashAttentionMode, .automatic)
        XCTAssertEqual(settings.promptTemplateMode, .litter)
        XCTAssertFalse(settings.kvUnified)
        XCTAssertEqual(settings.yarnAttentionFactor, -1)
        XCTAssertEqual(settings.yarnBetaFast, -1)
        XCTAssertEqual(settings.yarnBetaSlow, -1)
        XCTAssertTrue(settings.parseSpecialTokens)
        XCTAssertEqual(settings.ropeScalingMode, .modelDefault)
    }

    func testRuntimeOptionsCarryAdvancedSettings() {
        var settings = LocalModelRuntimeSettings.defaults()
        settings.minP = 0.12
        settings.typicalP = 0.82
        settings.dynamicTemperatureRange = 0.4
        settings.dynamicTemperatureExponent = 2.5
        settings.mirostatMode = .v2
        settings.mirostatTau = 6
        settings.mirostatEta = 0.2
        settings.batchThreadCount = 3
        settings.gpuLayerCount = 24
        settings.mmapEnabled = false
        settings.mlockEnabled = true
        settings.checkTensors = true
        settings.flashAttentionMode = .enabled
        settings.offloadKQV = false
        settings.opOffload = false
        settings.swaFull = false
        settings.kvUnified = false
        settings.promptTemplateMode = .modelDefault
        settings.parseSpecialTokens = false
        settings.stopSequences = ["</s>", "<|eot_id|>"]
        settings.ropeScalingMode = .yarn
        settings.ropeFrequencyBase = 500_000
        settings.ropeFrequencyScale = 2
        settings.yarnExtensionFactor = 1
        settings.yarnAttentionFactor = 1.25
        settings.yarnBetaFast = 64
        settings.yarnBetaSlow = 2
        settings.yarnOriginalContext = 8192

        let options = LocalLlamaGenerationOptions.from(settings: settings, turboQuantAvailable: false)

        XCTAssertEqual(options.minP, 0.12)
        XCTAssertEqual(options.typicalP, 0.82)
        XCTAssertEqual(options.dynamicTemperatureRange, 0.4)
        XCTAssertEqual(options.dynamicTemperatureExponent, 2.5)
        XCTAssertEqual(options.mirostatMode, .v2)
        XCTAssertEqual(options.mirostatTau, 6)
        XCTAssertEqual(options.mirostatEta, 0.2)
        XCTAssertEqual(options.batchThreadCount, 3)
        XCTAssertEqual(options.gpuLayerCount, DeviceCapabilityProfile.current().hasMetal ? 24 : 0)
        XCTAssertFalse(options.mmapEnabled)
        XCTAssertTrue(options.mlockEnabled)
        XCTAssertTrue(options.checkTensors)
        XCTAssertEqual(options.flashAttentionMode, .enabled)
        XCTAssertEqual(options.promptTemplateMode, .modelDefault)
        XCTAssertFalse(options.parseSpecialTokens)
        XCTAssertEqual(options.stopSequences, ["</s>", "<|eot_id|>"])
        XCTAssertEqual(options.ropeScalingMode, .yarn)
        XCTAssertEqual(options.ropeFrequencyBase, 500_000)
        XCTAssertEqual(options.yarnAttentionFactor, 1.25)
        XCTAssertEqual(options.yarnOriginalContext, 8192)
    }

    func testSanitizerClampsAdvancedSettingsAndDropsBlankStops() {
        var settings = LocalModelRuntimeSettings.defaults()
        settings.minP = -1
        settings.typicalP = 4
        settings.dynamicTemperatureRange = 20
        settings.dynamicTemperatureExponent = 0
        settings.mirostatTau = 100
        settings.mirostatEta = 0
        settings.batchThreadCount = 999
        settings.gpuLayerCount = 999
        settings.stopSequences = ["", "  ", "END\n"]
        settings.ropeFrequencyBase = -5
        settings.ropeFrequencyScale = 999
        settings.yarnExtensionFactor = -5
        settings.yarnOriginalContext = 999_999

        let sanitized = settings.sanitized(turboQuantAvailable: false)

        XCTAssertEqual(sanitized.minP, 0)
        XCTAssertEqual(sanitized.typicalP, 1)
        XCTAssertEqual(sanitized.dynamicTemperatureRange, 2)
        XCTAssertEqual(sanitized.dynamicTemperatureExponent, 0.1)
        XCTAssertEqual(sanitized.mirostatTau, 20)
        XCTAssertEqual(sanitized.mirostatEta, 0.001)
        XCTAssertLessThanOrEqual(sanitized.batchThreadCount, max(1, ProcessInfo.processInfo.processorCount))
        XCTAssertLessThanOrEqual(sanitized.gpuLayerCount, 512)
        XCTAssertEqual(sanitized.stopSequences, ["END"])
        XCTAssertEqual(sanitized.ropeFrequencyBase, 0)
        XCTAssertEqual(sanitized.ropeFrequencyScale, 100)
        XCTAssertEqual(sanitized.yarnExtensionFactor, -1)
        XCTAssertEqual(sanitized.yarnOriginalContext, 131_072)
    }
}
