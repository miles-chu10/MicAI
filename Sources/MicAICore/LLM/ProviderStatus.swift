import Foundation

public enum ProviderStatus: Sendable, Equatable {
  case notConfigured
  case readyToAttempt
  case retryingCredential
  case failed(MicAIError)

  public var summary: String {
    switch self {
    case .notConfigured:
      "Configure a command hotkey and model."
    case .readyToAttempt:
      "Codex credential will be checked when a command runs."
    case .retryingCredential:
      "Reloading the Codex credential after authorization failed."
    case .failed(let error):
      error.localizedDescription
    }
  }
}
