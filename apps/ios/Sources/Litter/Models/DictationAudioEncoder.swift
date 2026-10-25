import Foundation

/// An owned, immutable mono snapshot copied from an audio-engine tap.
struct RecordedAudioChunk: Sendable {
    let sampleRate: Double
    let samples: [Float]
}

/// Stateless conversion runs on a detached task, away from the UI actor.
enum DictationAudioEncoder {
    private static let targetSampleRate: Double = 24_000

    static func encodeWAV(_ buffers: [RecordedAudioChunk]) -> Data? {
        guard let first = buffers.first else { return nil }

        let srcRate = first.sampleRate
        let targetRate = Self.targetSampleRate
        guard srcRate.isFinite, srcRate > 0 else { return nil }

        var allSamples = [Float]()
        for buf in buffers {
            guard !Task.isCancelled, buf.sampleRate == srcRate else { return nil }
            allSamples.append(contentsOf: buf.samples)
        }
        guard !allSamples.isEmpty else { return nil }

        let resampled: [Int16]
        if abs(srcRate - targetRate) < 1.0 {
            resampled = allSamples.map { Self.floatToInt16($0) }
        } else {
            let ratio = targetRate / srcRate
            let scaledCount = Double(allSamples.count) * ratio
            guard scaledCount.isFinite, scaledCount > 0,
                  scaledCount <= Double((UInt32.max - 36) / 2) else { return nil }
            let outCount = Int(scaledCount)
            var out = [Int16](repeating: 0, count: outCount)
            for i in 0..<outCount {
                if i.isMultiple(of: 4096), Task.isCancelled { return nil }
                let srcIdx = Double(i) / ratio
                let idx = Int(srcIdx)
                let frac = Float(srcIdx - Double(idx))
                let s0 = allSamples[min(idx, allSamples.count - 1)]
                let s1 = allSamples[min(idx + 1, allSamples.count - 1)]
                out[i] = Self.floatToInt16(s0 + frac * (s1 - s0))
            }
            resampled = out
        }

        guard Float(resampled.count) / Float(targetRate) >= 0.5 else { return nil }

        guard !Task.isCancelled, resampled.count <= Int((UInt32.max - 36) / 2) else { return nil }
        let dataSize = resampled.count * 2
        var wav = Data(capacity: 44 + dataSize)
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLE(UInt32(36 + dataSize))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLE(UInt32(16))
        wav.appendLE(UInt16(1)) // PCM
        wav.appendLE(UInt16(1)) // mono
        wav.appendLE(UInt32(UInt32(targetRate)))
        wav.appendLE(UInt32(UInt32(targetRate) * 2)) // byte rate
        wav.appendLE(UInt16(2)) // block align
        wav.appendLE(UInt16(16)) // bits per sample
        wav.append(contentsOf: "data".utf8)
        wav.appendLE(UInt32(dataSize))
        resampled.withUnsafeBufferPointer { ptr in
            wav.append(contentsOf: UnsafeRawBufferPointer(ptr))
        }
        return wav
    }

    private static func floatToInt16(_ value: Float) -> Int16 {
        guard value.isFinite else { return 0 }
        return Int16(max(-1, min(1, value)) * Float(Int16.max))
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
