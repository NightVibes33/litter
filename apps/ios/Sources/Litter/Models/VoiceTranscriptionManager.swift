import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceTranscriptionManager {
    var isRecording = false
    var isTranscribing = false
    var audioLevel: Float = 0
    var error: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private let bufferCollector = AudioBufferCollector()

    private static let transcribeModel = "gpt-4o-mini-transcribe"

    func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() {
        guard !isRecording, !isTranscribing else { return }
        bufferCollector.reset()
        error = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: .defaultToSpeaker)
            try session.setActive(true)
        } catch {
            self.error = "Failed to configure audio session."
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate.isFinite, format.sampleRate > 0 else {
            error = "No microphone input is available."
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        let collector = bufferCollector

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            collector.append(buffer)
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard collector.shouldPublishLevel(at: now) else { return }
            let level = Self.rms(buffer: buffer)
            Task { @MainActor in
                guard self.isRecording else { return }
                self.audioLevel = level
            }
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            bufferCollector.reset()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            self.error = "Failed to start audio engine."
            return
        }

        audioEngine = engine
        isRecording = true
    }

    func stopAndTranscribe(authMethod: AuthMode?, authToken: String?) async -> String? {
        guard isRecording else { return nil }
        teardownEngine()
        let chunks = bufferCollector.drain()

        guard let authToken, !authToken.isEmpty else {
            error = "Not logged in."
            return nil
        }

        isTranscribing = true
        defer { isTranscribing = false }
        let encoding = Task.detached(priority: .userInitiated) {
            DictationAudioEncoder.encodeWAV(chunks)
        }
        let encoded = await withTaskCancellationHandler {
            await encoding.value
        } onCancel: {
            encoding.cancel()
        }
        guard !Task.isCancelled else { return nil }
        guard let wav = encoded else {
            error = "Failed to encode audio."
            return nil
        }

        do {
            return try await transcribe(wav: wav, authMethod: authMethod, token: authToken)
        } catch let err {
            self.error = err.localizedDescription
            return nil
        }
    }

    func cancelRecording() {
        teardownEngine()
        bufferCollector.reset()
    }

    // MARK: - Private

    private func teardownEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func transcribe(wav: Data, authMethod: AuthMode?, token: String) async throws -> String {
        let isChatGPT = authMethod == .chatgpt || authMethod == .chatgptAuthTokens

        let url: URL
        if isChatGPT {
            url = URL(string: "https://chatgpt.com/backend-api/transcribe")!
        } else {
            url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        if !isChatGPT {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(Self.transcribeModel)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "Transcription", code: status, userInfo: [
                NSLocalizedDescriptionKey: "Transcription failed (\(status))"
            ])
        }

        struct TranscriptionResponse: Decodable { let text: String }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
    }

    nonisolated private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        guard sum.isFinite else { return 0 }
        return min(sqrtf(sum / Float(count)) * 3, 1.0)
    }
}

final class AudioBufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [RecordedAudioChunk] = []
    private var lastLevelUpdate: CFAbsoluteTime = 0

    func shouldPublishLevel(at now: CFAbsoluteTime) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard now - lastLevelUpdate > 0.05 else { return false }
        lastLevelUpdate = now
        return true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.channelCount > 0, let samples = buffer.floatChannelData?[0] else { return }
        let chunk = RecordedAudioChunk(
            sampleRate: buffer.format.sampleRate,
            samples: Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        )
        lock.lock()
        buffers.append(chunk)
        lock.unlock()
    }

    func drain() -> [RecordedAudioChunk] {
        lock.lock()
        let result = buffers
        buffers = []
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        lastLevelUpdate = 0
        buffers = []
        lock.unlock()
    }
}
