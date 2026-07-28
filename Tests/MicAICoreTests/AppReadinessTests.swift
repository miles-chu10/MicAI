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
}
