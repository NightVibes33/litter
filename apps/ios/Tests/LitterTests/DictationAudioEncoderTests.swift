import Foundation
import XCTest
@testable import Litter

final class DictationAudioEncoderTests: XCTestCase {
    func testHalfSecondMonoRecordingProduces24kHzPCMHeaderAndSamples() throws {
        let wav = try XCTUnwrap(DictationAudioEncoder.encodeWAV([
            RecordedAudioChunk(sampleRate: 24_000, samples: Array(repeating: 0.5, count: 12_000))
        ]))
        XCTAssertEqual(wav.count, 44 + 24_000)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(Array(wav[24..<28]), [0xC0, 0x5D, 0, 0])
        XCTAssertEqual(Array(wav[44..<46]), [0xFF, 0x3F])
    }

    func test48kHzRecordingResamplesTo24kHz() throws {
        let wav = try XCTUnwrap(DictationAudioEncoder.encodeWAV([
            RecordedAudioChunk(sampleRate: 48_000, samples: Array(repeating: -1, count: 24_000))
        ]))
        XCTAssertEqual(wav.count, 44 + 24_000)
        XCTAssertEqual(Array(wav[44..<46]), [0x01, 0x80])
    }

    func testInvalidRatesMixedFormatsAndShortRecordingsAreRejected() {
        for rate in [0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(DictationAudioEncoder.encodeWAV([
                RecordedAudioChunk(sampleRate: rate, samples: [0])
            ]))
        }
        XCTAssertNil(DictationAudioEncoder.encodeWAV([]))
        XCTAssertNil(DictationAudioEncoder.encodeWAV([RecordedAudioChunk(sampleRate: 24_000, samples: [0])]))
        XCTAssertNil(DictationAudioEncoder.encodeWAV([
            RecordedAudioChunk(sampleRate: 24_000, samples: [0]),
            RecordedAudioChunk(sampleRate: 48_000, samples: [0])
        ]))
    }

    func testNonfiniteSamplesEncodeAsSilenceInsteadOfTrapping() throws {
        var samples = Array(repeating: Float.zero, count: 12_000)
        samples[0] = .nan
        samples[1] = .infinity
        let wav = try XCTUnwrap(DictationAudioEncoder.encodeWAV([
            RecordedAudioChunk(sampleRate: 24_000, samples: samples)
        ]))
        XCTAssertEqual(Array(wav[44..<48]), [0, 0, 0, 0])
    }
}
