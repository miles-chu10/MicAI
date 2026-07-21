import Foundation

public struct Transcript: Sendable, Equatable {
  public let text: String
  public let audioDuration: TimeInterval
  public let processingDuration: TimeInterval
  public let confidence: Float

  public init(
    text: String,
    audioDuration: TimeInterval,
    processingDuration: TimeInterval,
    confidence: Float
  ) {
    self.text = text
    self.audioDuration = audioDuration
    self.processingDuration = processingDuration
    self.confidence = confidence
  }
}
