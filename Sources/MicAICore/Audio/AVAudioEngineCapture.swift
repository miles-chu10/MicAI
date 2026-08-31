@preconcurrency import AVFoundation
import FluidAudio
import Foundation

public actor AVAudioEngineCapture: AudioCapturing {
  private static let targetSampleRate = 16_000
  public static let maximumDurationSeconds: Double = 120

  private var engine: AVAudioEngine?
  private var accumulator: AudioAccumulator?

  public init() {}

  public func start(
    levels: @escaping @Sendable (Float) -> Void,
    maximumDurationReached: @escaping @Sendable () -> Void
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
      maximumDurationSeconds: Self.maximumDurationSeconds,
      levels: levels,
      maximumDurationReached: maximumDurationReached
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
    let samples: [Float]
    do {
      samples = try Self.resampleForRecognition(
        capture.samples,
        from: capture.sampleRate
      )
    } catch {
      throw MicAIError.audioUnavailable
    }
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

  nonisolated static func resampleForRecognition(
    _ samples: [Float],
    from sampleRate: Double
  ) throws -> [Float] {
    try AudioConverter().resample(samples, from: sampleRate)
  }
}

final class AudioAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private let sampleRate: Double
  private let maximumSampleCount: Int
  private let levels: @Sendable (Float) -> Void
  private let maximumDurationReached: @Sendable () -> Void
  private var samples: [Float] = []
  private var didReachMaximumDuration = false

  init(
    sampleRate: Double,
    maximumDurationSeconds: Double,
    levels: @escaping @Sendable (Float) -> Void,
    maximumDurationReached: @escaping @Sendable () -> Void
  ) {
    self.sampleRate = sampleRate
    maximumSampleCount = max(
      1,
      Int((sampleRate * maximumDurationSeconds).rounded(.down))
    )
    self.levels = levels
    self.maximumDurationReached = maximumDurationReached
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
    let remainingCapacity = max(0, maximumSampleCount - samples.count)
    if remainingCapacity > 0 {
      samples.append(contentsOf: mono.prefix(remainingCapacity))
    }
    let shouldNotify =
      !didReachMaximumDuration && samples.count == maximumSampleCount
    if shouldNotify {
      didReachMaximumDuration = true
    }
    lock.unlock()

    levels(level)
    if shouldNotify {
      maximumDurationReached()
    }
  }

  func finish() -> (samples: [Float], sampleRate: Double) {
    lock.lock()
    defer { lock.unlock() }
    return (samples, sampleRate)
  }
}
