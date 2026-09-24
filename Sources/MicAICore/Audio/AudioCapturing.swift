import Foundation

public struct RecordedAudio: Sendable, Equatable {
  public let samples: [Float]
  public let sampleRate: Int
  public let duration: Duration

  public init(samples: [Float], sampleRate: Int, duration: Duration) {
    self.samples = samples
    self.sampleRate = sampleRate
    self.duration = duration
  }
}

/// The most recent stretch of a recording still in progress, for live preview.
public struct AudioSnapshot: Sendable, Equatable {
  /// Up to the requested duration of the newest audio, at 16 kHz mono.
  public let samples: [Float]
  /// How long the whole recording is so far, which can exceed `samples`.
  public let totalDuration: Duration

  public init(samples: [Float], totalDuration: Duration) {
    self.samples = samples
    self.totalDuration = totalDuration
  }
}

public protocol AudioCapturing: Sendable {
  func start(levels: @escaping @Sendable (Float) -> Void) async throws
  func stop() async throws -> RecordedAudio
  func cancel() async
  /// The newest `tail` of audio without stopping, or nil when not recording or
  /// when the capture cannot provide one.
  func snapshot(tail: Duration) async -> AudioSnapshot?
}

extension AudioCapturing {
  public func snapshot(tail: Duration) async -> AudioSnapshot? {
    nil
  }
}
