import Foundation

public enum MicAIError: Error, Equatable, Sendable {
  case operationAlreadyActive
  case invalidTransition
  case cancelled
  case microphoneDenied
  case accessibilityDenied
  case audioAlreadyRecording
  case audioUnavailable
  case audioTooShort
  case modelDownloadFailed
  case asrNotInitialized
  case asrFailed
  case targetChanged
  case clipboardChanged
  case insertionFailed
}

extension MicAIError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .operationAlreadyActive:
      "Another operation is already active."
    case .invalidTransition:
      "The operation cannot move to the requested phase."
    case .cancelled:
      "The operation was cancelled."
    case .microphoneDenied:
      "Microphone access is required."
    case .accessibilityDenied:
      "Accessibility access is required."
    case .audioAlreadyRecording:
      "Audio capture is already active."
    case .audioUnavailable:
      "Audio input is unavailable."
    case .audioTooShort:
      "The recording is too short to transcribe."
    case .modelDownloadFailed:
      "The speech model could not be prepared."
    case .asrNotInitialized:
      "The speech model is not ready."
    case .asrFailed:
      "Speech recognition failed."
    case .targetChanged:
      "The target application changed before insertion."
    case .clipboardChanged:
      "The clipboard changed before it could be restored."
    case .insertionFailed:
      "Text insertion failed."
    }
  }
}
