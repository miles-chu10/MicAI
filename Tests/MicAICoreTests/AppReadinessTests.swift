import MicAICore
import Testing

@Suite
struct AppReadinessTests {
  @Test
  func dictationCanBeReadyWhileCommandsRemainBlocked() {
    let readiness = AppReadiness(
      microphoneGranted: true,
      accessibilityGranted: true,
      speechModelReady: true,
      commandHotkeyConfigured: false,
      languageModelConfigured: false,
      operationActive: false
    )

    #expect(readiness.dictation.isReady)
    #expect(
      readiness.command.blockers == [.commandHotkey, .languageModel]
    )
  }

  @Test
  func sharedBlockersApplyToBothFeaturesInStableOrder() {
    let readiness = AppReadiness(
      microphoneGranted: false,
      accessibilityGranted: false,
      speechModelReady: false,
      commandHotkeyConfigured: true,
      languageModelConfigured: true,
      operationActive: true
    )

    let expected: [ReadinessBlocker] = [
      .microphone, .accessibility, .speechModel, .activeOperation,
    ]
    #expect(readiness.dictation.blockers == expected)
    #expect(readiness.command.blockers == expected)
  }

  @Test
  func savedResultBlocksNewWorkUntilResolved() {
    let readiness = AppReadiness(
      microphoneGranted: true,
      accessibilityGranted: true,
      speechModelReady: true,
      commandHotkeyConfigured: true,
      languageModelConfigured: true,
      operationActive: false,
      recoveryPending: true
    )

    #expect(readiness.dictation.blockers == [.recoveryPending])
    #expect(readiness.command.blockers == [.recoveryPending])
    #expect(readiness.dictation.isSetupReady)
    #expect(!readiness.dictation.isBusy)
    #expect(readiness.dictation.hasPendingRecovery)
  }

  @Test
  func activeOperationDoesNotReduceSetupReadiness() {
    let readiness = AppReadiness(
      microphoneGranted: true,
      accessibilityGranted: true,
      speechModelReady: true,
      commandHotkeyConfigured: true,
      languageModelConfigured: true,
      operationActive: true
    )

    #expect(!readiness.dictation.isReady)
    #expect(readiness.dictation.isSetupReady)
    #expect(readiness.dictation.setupBlockers.isEmpty)
    #expect(readiness.dictation.isBusy)
    #expect(readiness.command.isSetupReady)
    #expect(readiness.command.isBusy)
  }

  @Test
  func setupBlockersExcludeOnlyTransientWork() {
    let readiness = AppReadiness(
      microphoneGranted: false,
      accessibilityGranted: true,
      speechModelReady: false,
      commandHotkeyConfigured: false,
      languageModelConfigured: true,
      operationActive: true,
      recoveryPending: true
    )

    #expect(
      readiness.dictation.setupBlockers == [.microphone, .speechModel]
    )
    #expect(
      readiness.command.setupBlockers
        == [.microphone, .speechModel, .commandHotkey]
    )
  }

  @Test
  func openAIWithoutFallbackDoesNotRequireParakeetButRequiresConfiguration() {
    let readiness = AppReadiness(
      microphoneGranted: true,
      accessibilityGranted: true,
      speechModelReady: false,
      commandHotkeyConfigured: true,
      languageModelConfigured: true,
      operationActive: false,
      dictationProvider: .openAI,
      openAITranscriptionConfigured: false,
      dictationFallbackEnabled: false
    )

    #expect(readiness.dictation.blockers == [.dictationProvider])
    #expect(readiness.command.blockers == [.speechModel])
  }

  @Test
  func openAIFallbackRequiresParakeetAndBecomesReadyWhenPrepared() {
    let blocked = AppReadiness(
      microphoneGranted: true,
      accessibilityGranted: true,
      speechModelReady: false,
      commandHotkeyConfigured: false,
      languageModelConfigured: false,
      operationActive: false,
      dictationProvider: .openAI,
      openAITranscriptionConfigured: false,
      dictationFallbackEnabled: true
    )
    #expect(blocked.dictation.blockers == [.speechModel])

    let fallbackReady = AppReadiness(
      microphoneGranted: true,
      accessibilityGranted: true,
      speechModelReady: true,
      commandHotkeyConfigured: false,
      languageModelConfigured: false,
      operationActive: false,
      dictationProvider: .openAI,
      openAITranscriptionConfigured: false,
      dictationFallbackEnabled: true
    )
    #expect(fallbackReady.dictation.isReady)
    #expect(
      fallbackReady.command.blockers == [.commandHotkey, .languageModel]
    )
  }
}
