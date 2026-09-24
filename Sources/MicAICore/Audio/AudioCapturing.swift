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

public protocol AudioCapturing: Sendable {
  func start(
    levels: @escaping @Sendable (Float) -> Void,
    maximumDurationReached: @escaping @Sendable () -> Void
  ) async throws
  func stop() async throws -> RecordedAudio
  func cancel() async
}
