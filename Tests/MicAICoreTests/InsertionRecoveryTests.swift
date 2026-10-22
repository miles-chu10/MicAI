import MicAICore
import Testing

@Suite
struct InsertionRecoveryTests {
  @Test(arguments: [
    MicAIError.accessibilityDenied, .targetChanged, .insertionFailed,
    .clipboardRestoreFailedBeforeInsertion,
  ])
  func failedInsertionKeepsTheFinishedText(error: MicAIError) {
    var recovery = InsertionRecovery()
    recovery.prepare("- Ship Tuesday\n- Review at 3 PM")

    let outcome = recovery.outcome(for: error)

    #expect(outcome.keptText == "- Ship Tuesday\n- Review at 3 PM")
    #expect(outcome.message.hasPrefix(error.localizedDescription))
    #expect(outcome.message.hasSuffix(InsertionRecovery.hint))
  }

  @Test
  func cancellingKeepsNothing() {
    var recovery = InsertionRecovery()
    recovery.prepare("please send the draft on Tuesday at 3 PM")

    let outcome = recovery.outcome(for: .cancelled)

    #expect(outcome.keptText == nil)
    #expect(outcome.message == MicAIError.cancelled.localizedDescription)
  }

  @Test
  func failuresBeforeTheTextExistedKeepNothing() {
    let outcome = InsertionRecovery().outcome(for: .llmRateLimited)
    #expect(outcome.keptText == nil)
    #expect(outcome.message == MicAIError.llmRateLimited.localizedDescription)
  }

  @Test
  func resetForgetsTheTextSoALaterOperationCannotSurfaceIt() {
    var recovery = InsertionRecovery()
    recovery.prepare("old answer")
    recovery.reset()

    #expect(recovery.outcome(for: .targetChanged).keptText == nil)
  }

  @Test
  func emptyTextIsNotKept() {
    var recovery = InsertionRecovery()
    recovery.prepare("")
    #expect(recovery.outcome(for: .targetChanged).keptText == nil)
  }
}
