import AVFoundation
import Foundation
import Testing
@testable import MicAICore

@Suite
struct AudioCaptureSupportTests {
  @Test
  func accumulatorCapsRecordingAndNotifiesOnce() throws {
    let callback = LockedCallbackCounter()
    let accumulator = AudioAccumulator(
      sampleRate: 10,
      maximumDurationSeconds: 1,
      levels: { _ in },
      maximumDurationReached: callback.increment
    )

    let buffer = try makeBuffer(frameCount: 7, sampleRate: 10)
    accumulator.append(buffer)
    accumulator.append(buffer)
    accumulator.append(buffer)

    let capture = accumulator.finish()
    #expect(capture.samples.count == 10)
    #expect(capture.sampleRate == 10)
    #expect(callback.count == 1)
  }

  @Test
  func resamplingUsesRecognitionFormat() throws {
    let sampleRate = 48_000.0
    let samples = (0..<4_800).map { index in
      Float(sin(2 * .pi * 440 * Double(index) / sampleRate))
    }

    let converted = try AVAudioEngineCapture.resampleForRecognition(
      samples,
      from: sampleRate
    )

    #expect((1_550...1_650).contains(converted.count))
    #expect(converted.allSatisfy { $0.isFinite })
  }

  private func makeBuffer(
    frameCount: AVAudioFrameCount,
    sampleRate: Double
  ) throws -> AVAudioPCMBuffer {
    let format = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    )
    let buffer = try #require(
      AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    )
    buffer.frameLength = frameCount
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(frameCount) {
      channel[index] = 0.25
    }
    return buffer
  }
}

private final class LockedCallbackCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storedCount = 0

  var count: Int {
    lock.lock()
    defer {
      lock.unlock()
    }
    return storedCount
  }

  func increment() {
    lock.lock()
    storedCount += 1
    lock.unlock()
  }
}
