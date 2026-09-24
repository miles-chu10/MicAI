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
      commandProviderAvailable: true,
      operationActive: false
    )

    #expect(readiness.dictation.isReady)
    #expect(readiness.command.blockers == [.commandHotkey])
  }

  @Test
  func sharedBlockersApplyToBothFeaturesInStableOrder() {
    let readiness = AppReadiness(
      microphoneGranted: false,
      accessibilityGranted: false,
      speechModelReady: false,
      commandHotkeyConfigured: true,
      commandProviderAvailable: true,
      operationActive: true
    )

    let expected: [ReadinessBlocker] = [
      .microphone, .accessibility, .speechModel, .activeOperation,
    ]
    #expect(readiness.dictation.blockers == expected)
    #expect(readiness.command.blockers == expected)
  }

  @Test
  func missingCodexCLIBlocksCommandsOnly() {
    let readiness = AppReadiness(
      microphoneGranted: true,
      accessibilityGranted: true,
      speechModelReady: true,
      commandHotkeyConfigured: true,
      commandProviderAvailable: false,
      operationActive: false
    )

    #expect(readiness.dictation.isReady)
    #expect(readiness.command.blockers == [.commandProvider])
  }
}
