import Foundation

public enum DictationProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case openAI
  case parakeet

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .openAI:
      "OpenAI — Recommended"
    case .parakeet:
      "Parakeet — On-device"
    }
  }

  public var shortName: String {
    switch self {
    case .openAI:
      "OpenAI"
    case .parakeet:
      "Parakeet"
    }
  }
}

public struct SpeechTranscriptionRequest: Sendable, Equatable {
  public static let defaultOpenAIModel = "gpt-transcribe"
  public static let localParakeet = SpeechTranscriptionRequest(
    provider: .parakeet,
    model: defaultOpenAIModel,
    fallbackToParakeet: true
  )

  public let provider: DictationProvider
  public let model: String
  public let fallbackToParakeet: Bool

  public init(
    provider: DictationProvider,
    model: String = SpeechTranscriptionRequest.defaultOpenAIModel,
    fallbackToParakeet: Bool = true
  ) {
    self.provider = provider
    self.model = model
    self.fallbackToParakeet = fallbackToParakeet
  }
}
