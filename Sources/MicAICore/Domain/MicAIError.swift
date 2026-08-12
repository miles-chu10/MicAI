import Foundation

public enum MicAIError: Error, Equatable, Sendable {
  case operationAlreadyActive
  case recoveryPending
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
  case audioUploadTooLarge
  case transcriptionNotConfigured
  case transcriptionUnauthorized
  case transcriptionForbidden
  case transcriptionRateLimited
  case transcriptionTimedOut
  case transcriptionServerFailure
  case transcriptionIncomplete
  case credentialMissing
  case credentialMalformed
  case llmUnauthorized
  case llmForbidden
  case llmRateLimited
  case llmServerFailure
  case llmIncomplete
  case targetChanged
  case clipboardChanged
  case clipboardRestoreFailedAfterCancellation
  case clipboardRestoreFailedAfterTargetChange
  case clipboardRestoreFailedBeforeInsertion
  case clipboardRestoreFailedAfterInsertion
  case insertionFailed
}

extension MicAIError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .operationAlreadyActive:
      "Another operation is already active."
    case .recoveryPending:
      "Retry, copy, or dismiss the saved result before recording again."
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
    case .audioUploadTooLarge:
      "The recording is too large for OpenAI transcription."
    case .transcriptionNotConfigured:
      "OpenAI transcription is not configured."
    case .transcriptionUnauthorized:
      "OpenAI transcription could not authorize this API key."
    case .transcriptionForbidden:
      "OpenAI transcription is not available for this API project."
    case .transcriptionRateLimited:
      "OpenAI transcription is temporarily rate limited."
    case .transcriptionTimedOut:
      "OpenAI transcription timed out."
    case .transcriptionServerFailure:
      "OpenAI transcription is temporarily unavailable."
    case .transcriptionIncomplete:
      "OpenAI transcription returned no usable text."
    case .credentialMissing:
      "Sign in with Codex before using AI Commands."
    case .credentialMalformed:
      "The Codex credential file could not be read."
    case .llmUnauthorized:
      "The Codex session is no longer authorized. Sign in again and retry."
    case .llmForbidden:
      "The ChatGPT command route is not available for this account."
    case .llmRateLimited:
      "AI Commands are temporarily rate limited. Try again shortly."
    case .llmServerFailure:
      "The language model service is unavailable."
    case .llmIncomplete:
      "The language model returned an incomplete response."
    case .targetChanged:
      "The target application changed before insertion."
    case .clipboardChanged:
      "The clipboard changed before it could be restored."
    case .clipboardRestoreFailedAfterCancellation:
      "The operation was cancelled, but the original clipboard could not be restored."
    case .clipboardRestoreFailedAfterTargetChange:
      "Insertion was withheld after the target changed, but the original clipboard could not be restored."
    case .clipboardRestoreFailedBeforeInsertion:
      "Insertion failed before paste, and the original clipboard could not be restored."
    case .clipboardRestoreFailedAfterInsertion:
      "Paste was sent, but its completion is uncertain because the original clipboard could not be restored. Check the target before acting again."
    case .insertionFailed:
      "Text insertion failed."
    }
  }
}
