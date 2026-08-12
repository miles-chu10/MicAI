import Foundation
import MicAICore
import OSLog

enum MicAITelemetry {
  private static let logger = Logger(
    subsystem: "com.mileschu.micai",
    category: "Operations"
  )

  static func operationStarted(mode: MicAIMode) {
    logger.notice(
      "operation_started mode=\(mode.rawValue, privacy: .public)"
    )
  }

  static func operationEntered(_ phase: String, mode: MicAIMode) {
    logger.info(
      "operation_phase mode=\(mode.rawValue, privacy: .public) phase=\(phase, privacy: .public)"
    )
  }

  static func operationCompleted(mode: MicAIMode, duration: TimeInterval) {
    logger.notice(
      "operation_completed mode=\(mode.rawValue, privacy: .public) duration_seconds=\(duration, privacy: .public)"
    )
  }

  static func operationFailed(mode: MicAIMode, error: MicAIError) {
    logger.error(
      "operation_failed mode=\(mode.rawValue, privacy: .public) error=\(error.telemetryCode, privacy: .public)"
    )
  }

  static func operationCancelled(mode: MicAIMode) {
    logger.notice(
      "operation_cancelled mode=\(mode.rawValue, privacy: .public)"
    )
  }

  static func recordingLimitReached(mode: MicAIMode) {
    logger.notice(
      "recording_limit_reached mode=\(mode.rawValue, privacy: .public)"
    )
  }

  static func recoveryCreated(mode: MicAIMode, error: MicAIError) {
    logger.notice(
      "insertion_recovery_created mode=\(mode.rawValue, privacy: .public) error=\(error.telemetryCode, privacy: .public)"
    )
  }

  static func recoveryCopied() {
    logger.notice("insertion_recovery_copied")
  }

  static func recoveryRetried(succeeded: Bool) {
    logger.notice(
      "insertion_recovery_retried succeeded=\(succeeded, privacy: .public)"
    )
  }

  static func recoveryDismissed() {
    logger.notice("insertion_recovery_dismissed")
  }
}

extension MicAIError {
  fileprivate var telemetryCode: String {
    switch self {
    case .operationAlreadyActive:
      "operation_already_active"
    case .recoveryPending:
      "recovery_pending"
    case .invalidTransition:
      "invalid_transition"
    case .cancelled:
      "cancelled"
    case .microphoneDenied:
      "microphone_denied"
    case .accessibilityDenied:
      "accessibility_denied"
    case .audioAlreadyRecording:
      "audio_already_recording"
    case .audioUnavailable:
      "audio_unavailable"
    case .audioTooShort:
      "audio_too_short"
    case .modelDownloadFailed:
      "model_download_failed"
    case .asrNotInitialized:
      "asr_not_initialized"
    case .asrFailed:
      "asr_failed"
    case .audioUploadTooLarge:
      "audio_upload_too_large"
    case .transcriptionNotConfigured:
      "transcription_not_configured"
    case .transcriptionUnauthorized:
      "transcription_unauthorized"
    case .transcriptionForbidden:
      "transcription_forbidden"
    case .transcriptionRateLimited:
      "transcription_rate_limited"
    case .transcriptionTimedOut:
      "transcription_timed_out"
    case .transcriptionServerFailure:
      "transcription_server_failure"
    case .transcriptionIncomplete:
      "transcription_incomplete"
    case .credentialMissing:
      "credential_missing"
    case .credentialMalformed:
      "credential_malformed"
    case .llmUnauthorized:
      "llm_unauthorized"
    case .llmForbidden:
      "llm_forbidden"
    case .llmRateLimited:
      "llm_rate_limited"
    case .llmServerFailure:
      "llm_server_failure"
    case .llmIncomplete:
      "llm_incomplete"
    case .targetChanged:
      "target_changed"
    case .clipboardChanged:
      "clipboard_changed"
    case .clipboardRestoreFailedAfterCancellation:
      "clipboard_restore_failed_after_cancellation"
    case .clipboardRestoreFailedAfterTargetChange:
      "clipboard_restore_failed_after_target_change"
    case .clipboardRestoreFailedBeforeInsertion:
      "clipboard_restore_failed_before_insertion"
    case .clipboardRestoreFailedAfterInsertion:
      "clipboard_restore_failed_after_insertion"
    case .insertionFailed:
      "insertion_failed"
    }
  }
}
