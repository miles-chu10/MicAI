@preconcurrency import AVFoundation
import Foundation

public actor AVAudioEngineCapture: AudioCapturing {
  private static let targetSampleRate = 16_000

  private var engine: AVAudioEngine?
  private var accumulator: AudioAccumulator?

  public init() {}

  public func start(
    levels: @escaping @Sendable (Float) -> Void
  ) async throws {
    guard engine == nil else {
      throw MicAIError.audioAlreadyRecording
    }

    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw MicAIError.audioUnavailable
    }

    let accumulator = AudioAccumulator(
      sampleRate: format.sampleRate,
      levels: levels
    )
    input.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: format
    ) { buffer, _ in
      accumulator.append(buffer)
    }

    do {
      engine.prepare()
      try engine.start()
      self.engine = engine
      self.accumulator = accumulator
    } catch {
      input.removeTap(onBus: 0)
      engine.stop()
      throw MicAIError.audioUnavailable
    }
  }

  public func stop() async throws -> RecordedAudio {
    guard let engine, let accumulator else {
      throw MicAIError.audioUnavailable
    }

    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    self.engine = nil
    self.accumulator = nil

    let capture = accumulator.finish()
    let samples = Self.resample(
      capture.samples,
      from: capture.sampleRate,
      to: Double(Self.targetSampleRate)
    )
    return RecordedAudio(
      samples: samples,
      sampleRate: Self.targetSampleRate,
      duration: .seconds(Double(samples.count) / Double(Self.targetSampleRate))
    )
  }

  public func cancel() async {
    guard let engine else {
      return
    }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    self.engine = nil
    accumulator = nil
  }

  private nonisolated static func resample(
    _ samples: [Float],
    from sourceRate: Double,
    to targetRate: Double
  ) -> [Float] {
    guard !samples.isEmpty, sourceRate > 0 else {
      return []
    }
    if sourceRate == targetRate {
      return samples
    }

    let outputCount = Int((Double(samples.count) * targetRate / sourceRate).rounded(.down))
    guard outputCount > 0 else {
      return []
    }

    let sourceStep = sourceRate / targetRate
    return (0..<outputCount).map { outputIndex in
      let sourcePosition = Double(outputIndex) * sourceStep
      let lowerIndex = min(Int(sourcePosition), samples.count - 1)
      let upperIndex = min(lowerIndex + 1, samples.count - 1)
      let fraction = Float(sourcePosition - Double(lowerIndex))
      return samples[lowerIndex] + ((samples[upperIndex] - samples[lowerIndex]) * fraction)
    }
  }
}

private final class AudioAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private let sampleRate: Double
  private let levels: @Sendable (Float) -> Void
  private var samples: [Float] = []

  init(sampleRate: Double, levels: @escaping @Sendable (Float) -> Void) {
    self.sampleRate = sampleRate
    self.levels = levels
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    guard let channels = buffer.floatChannelData else {
      return
    }

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 0, channelCount > 0 else {
      return
    }

    var mono = [Float](repeating: 0, count: frameCount)
    for channelIndex in 0..<channelCount {
      let channel = channels[channelIndex]
      for frameIndex in 0..<frameCount {
        mono[frameIndex] += channel[frameIndex] / Float(channelCount)
      }
    }
    for frameIndex in 0..<frameCount {
      mono[frameIndex] = min(1, max(-1, mono[frameIndex]))
    }

    let squareSum = mono.reduce(0) { partial, sample in
      partial + (sample * sample)
    }
    let level = min(1, sqrt(squareSum / Float(frameCount)))

    lock.lock()
    samples.append(contentsOf: mono)
    lock.unlock()
    levels(level)
  }

  func finish() -> (samples: [Float], sampleRate: Double) {
    lock.lock()
    defer { lock.unlock() }
    return (samples, sampleRate)
  }
}
