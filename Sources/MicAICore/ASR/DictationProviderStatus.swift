public enum DictationProviderStatus: Sendable, Equatable {
  case parakeetNotReady
  case parakeetReady
  case openAINotConfigured(fallbackEnabled: Bool, fallbackReady: Bool)
  case transcribing(DictationProvider)
  case fallingBackToParakeet(MicAIError)
  case completed(DictationProvider)
  case failed(DictationProvider, MicAIError)

  public var summary: String {
    switch self {
    case .parakeetNotReady:
      "Parakeet model not prepared"
    case .parakeetReady:
      "Parakeet on-device"
    case .openAINotConfigured(let fallbackEnabled, let fallbackReady):
      if fallbackEnabled, fallbackReady {
        "OpenAI not configured; Parakeet fallback will be used"
      } else if fallbackEnabled {
        "OpenAI not configured; prepare the Parakeet fallback"
      } else {
        "OpenAI not configured"
      }
    case .transcribing(let provider):
      "Transcribing with \(provider.shortName)"
    case .fallingBackToParakeet:
      "OpenAI unavailable; using Parakeet on-device"
    case .completed(let provider):
      "Last transcription completed with \(provider.shortName)"
    case .failed(_, let error):
      error.localizedDescription
    }
  }
}
