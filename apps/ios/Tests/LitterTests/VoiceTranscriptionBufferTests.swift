import AVFoundation
import XCTest
@testable import Litter

final class VoiceTranscriptionBufferTests: XCTestCase {
    func testCollectorCopiesReusableInputBuffers() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<4 { samples[index] = Float(index) / 4 }
        let collector = AudioBufferCollector()
        collector.append(buffer)
        // Audio-engine tap buffers may be reused after the callback returns.
        for index in 0..<4 { samples[index] = -1 }
        let saved = try XCTUnwrap(collector.drain().first)
        XCTAssertEqual(saved.samples.count, 4)
        XCTAssertEqual(saved.sampleRate, 24_000)
        for index in 0..<4 { XCTAssertEqual(saved.samples[index], Float(index) / 4) }
        XCTAssertTrue(collector.drain().isEmpty)
    }

    func testResetReleasesAudioAndResetsMeterThrottle() throws {
        let collector = AudioBufferCollector()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 1
        collector.append(buffer)
        XCTAssertTrue(collector.shouldPublishLevel(at: 10))
        XCTAssertFalse(collector.shouldPublishLevel(at: 10.01))
        collector.reset()
        XCTAssertTrue(collector.drain().isEmpty)
        XCTAssertTrue(collector.shouldPublishLevel(at: 10.01))
    }
}
