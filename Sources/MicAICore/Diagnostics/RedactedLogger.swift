#if canImport(os)
  import os
#endif

public enum RedactedEvent: Sendable {
  case operationStarted(mode: MicAIMode)
  case phaseChanged(mode: MicAIMode, phase: OperationPhase)
  case operationCompleted(mode: MicAIMode)
  case operationFailed(mode: MicAIMode, error: MicAIError)
  case operationCancelled(mode: MicAIMode)
}

public struct RedactedLogger: Sendable {
  #if canImport(os)
    private let logger: Logger
  #endif

  public init() {
    #if canImport(os)
      logger = Logger(subsystem: "com.mileschu.micai", category: "operations")
    #endif
  }

  public func log(_ event: RedactedEvent) {
    #if canImport(os)
      logger.info("\(Self.message(for: event), privacy: .public)")
    #else
      _ = event
    #endif
  }

  public static func message(for event: RedactedEvent) -> String {
    switch event {
    case .operationStarted(let mode):
      "operationStarted mode=\(mode.rawValue)"
    case .phaseChanged(let mode, let phase):
      "phaseChanged mode=\(mode.rawValue) phase=\(phaseIdentifier(phase))"
    case .operationCompleted(let mode):
      "operationCompleted mode=\(mode.rawValue)"
    case .operationFailed(let mode, let error):
      "operationFailed mode=\(mode.rawValue) error=\(errorIdentifier(error))"
    case .operationCancelled(let mode):
      "operationCancelled mode=\(mode.rawValue)"
    }
  }

  private static func phaseIdentifier(_ phase: OperationPhase) -> String {
    switch phase {
    case .idle:
      "idle"
    case .recording:
      "recording"
    case .transcribing:
      "transcribing"
    case .awaitingLLM:
      "awaitingLLM"
    case .inserting:
      "inserting"
    case .failed(let error):
      "failed(\(errorIdentifier(error)))"
    }
  }

  private static func errorIdentifier(_ error: MicAIError) -> String {
    switch error {
    case .operationAlreadyActive:
      "operationAlreadyActive"
    case .invalidTransition:
      "invalidTransition"
    case .cancelled:
      "cancelled"
    case .microphoneDenied:
      "microphoneDenied"
    case .accessibilityDenied:
      "accessibilityDenied"
    case .audioAlreadyRecording:
      "audioAlreadyRecording"
    case .audioUnavailable:
      "audioUnavailable"
    case .audioTooShort:
      "audioTooShort"
    case .modelDownloadFailed:
      "modelDownloadFailed"
    case .asrNotInitialized:
      "asrNotInitialized"
    case .asrFailed:
      "asrFailed"
    case .credentialMissing:
      "credentialMissing"
    case .credentialMalformed:
      "credentialMalformed"
    case .llmUnauthorized:
      "llmUnauthorized"
    case .llmForbidden:
      "llmForbidden"
    case .llmRateLimited:
      "llmRateLimited"
    case .llmServerFailure:
      "llmServerFailure"
    case .llmIncomplete:
      "llmIncomplete"
    case .targetChanged:
      "targetChanged"
    case .clipboardChanged:
      "clipboardChanged"
    case .clipboardRestoreFailedAfterCancellation:
      "clipboardRestoreFailedAfterCancellation"
    case .clipboardRestoreFailedAfterTargetChange:
      "clipboardRestoreFailedAfterTargetChange"
    case .clipboardRestoreFailedBeforeInsertion:
      "clipboardRestoreFailedBeforeInsertion"
    case .insertionFailed:
      "insertionFailed"
    }
  }
}
