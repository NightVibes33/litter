import AVFoundation
import os

/// Keeps an `AVAudioSession` active for the lifetime of a PiP window.
///
/// Custom-content PiP (`AVPictureInPictureController` backed by an
/// `AVSampleBufferDisplayLayer`) requires an active audio session for the app
/// to remain eligible for background rendering, even though we never produce
/// audio. We satisfy this by setting `.playback` + `.mixWithOthers` and looping
/// a runtime-synthesised second of silence on an `AVAudioPlayer`.
///
/// To avoid stomping on the WebRTC voice session or the transcription
/// recorder, `activate()` is a no-op when the shared session is already
/// configured for `.playAndRecord` or `.playback` by someone else. In that
/// case PiP rides on the existing session and we leave configuration alone.
@MainActor
final class SilentAudioKeeper {
    private var player: AVAudioPlayer?
    private var claimedSession = false

    func activate() {
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // If a voice subsystem (RealtimeWebRtcSession / VoiceTranscriptionManager)
        // owns the session for I/O, leave it alone — `.playAndRecord` already
        // satisfies PiP's background-eligibility requirement.
        if session.category == .playAndRecord {
            return
        }
        // Otherwise (re)claim `.playback`. setCategory is safe to call even
        // when the category already matches — needed on the second activate
        // because the category persists across our previous setActive(false).
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            LLog.warn("pip", "SilentAudioKeeper.activate failed", fields: ["error": "\(error)"])
            return
        }
        claimedSession = true
        guard let buffer = Self.makeSilentLoopData() else { return }
        do {
            let p = try AVAudioPlayer(data: buffer)
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            LLog.warn("pip", "SilentAudioKeeper player init failed", fields: ["error": "\(error)"])
        }
    }

    func deactivate() {
        player?.stop()
        player = nil
        guard claimedSession else { return }
        claimedSession = false
        let session = AVAudioSession.sharedInstance()
        // If something else has taken over the session category, don't yank
        // it out from under them.
        guard session.category == .playback else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Builds an in-memory WAV containing 1s of 8 kHz 16-bit mono silence.
    /// Returning `Data` lets `AVAudioPlayer(data:)` consume it without ever
    /// touching disk or shipping an asset.
    private static func makeSilentLoopData() -> Data? {
        let sampleRate: UInt32 = 8000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let durationSamples: UInt32 = sampleRate
        let dataSize: UInt32 = durationSamples * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let byteRate: UInt32 = sampleRate * UInt32(blockAlign)

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(le32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(le32(16))
        data.append(le16(1)) // PCM
        data.append(le16(channels))
        data.append(le32(sampleRate))
        data.append(le32(byteRate))
        data.append(le16(blockAlign))
        data.append(le16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        data.append(le32(dataSize))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private static func le16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }

    private static func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }
}
