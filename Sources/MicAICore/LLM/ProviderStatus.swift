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
      "Personal preview: local Codex sign-in is checked when a command runs."
    case .retryingCredential:
      "Reloading the local Codex sign-in after authorization failed."
    case .failed(let error):
      error.localizedDescription
    }
  }
}
