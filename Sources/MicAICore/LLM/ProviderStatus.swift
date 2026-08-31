import Foundation

public enum ProviderStatus: Sendable, Equatable {
  case notConfigured
  case readyToAttempt
  case retryingCredential
  case apiKeyReadyToAttempt
  case apiKeyMissing
  case apiKeyFailed(MicAIError)
  case failed(MicAIError)

  public var summary: String {
    switch self {
    case .notConfigured:
      "Configure a command hotkey and model before using the ChatGPT subscription."
    case .readyToAttempt:
      "ChatGPT subscription credential will be checked when a command runs."
    case .retryingCredential:
      "Reloading the Codex credential after authorization failed."
    case .apiKeyReadyToAttempt:
      "OPENAI_API_KEY is configured and will be used for AI Commands."
    case .apiKeyMissing:
      "OPENAI_API_KEY is not set in MicAI's environment."
    case .apiKeyFailed(let error):
      Self.apiKeyFailureSummary(for: error)
    case .failed(let error):
      error.localizedDescription
    }
  }

  private static func apiKeyFailureSummary(for error: MicAIError) -> String {
    switch error {
    case .credentialMissing:
      "OPENAI_API_KEY is not set in MicAI's environment."
    case .llmUnauthorized:
      "OPENAI_API_KEY was rejected by the OpenAI API."
    case .llmForbidden:
      "OPENAI_API_KEY does not have access to this OpenAI API request."
    case .llmRateLimited:
      "OpenAI API requests are temporarily rate limited."
    case .llmServerFailure:
      "The OpenAI API is unavailable."
    case .llmIncomplete:
      "The OpenAI API returned an incomplete response."
    default:
      error.localizedDescription
    }
  }
}
