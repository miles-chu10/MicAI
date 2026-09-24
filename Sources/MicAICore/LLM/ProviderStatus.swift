import Foundation

public enum ProviderStatus: Sendable, Equatable {
  case notConfigured
  case readyToAttempt
  case retryingCredential
  case failed(MicAIError)

  public var summary: String {
    switch self {
    case .notConfigured:
      "Choose a command hotkey to enable ChatGPT Command Mode."
    case .readyToAttempt:
      "Uses your signed-in Codex CLI and ChatGPT subscription."
    case .retryingCredential:
      "Retrying after the Codex CLI authorization failed."
    case .failed(let error):
      error.localizedDescription
    }
  }
}
