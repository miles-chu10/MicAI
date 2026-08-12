import Foundation

public enum ProviderStatus: Sendable, Equatable {
  case notConfigured
  case readyToAttempt
  case retryingCredential
  case failed(MicAIError)

  public func summary(for provider: LLMProvider) -> String {
    switch self {
    case .notConfigured:
      "Configure a command hotkey and model."
    case .readyToAttempt:
      switch provider {
      case .openAIAPIKey:
        "The OPENAI_API_KEY environment variable will be checked when a command runs."
      case .chatGPTSubscription:
        "Codex credential will be checked when a command runs."
      }
    case .retryingCredential:
      switch provider {
      case .openAIAPIKey:
        "Rechecking authorization with the OpenAI API."
      case .chatGPTSubscription:
        "Reloading the Codex credential after authorization failed."
      }
    case .failed(let error):
      error.localizedDescription
    }
  }
}
