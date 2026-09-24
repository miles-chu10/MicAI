import Foundation
import Testing

@testable import MicAICore

@Suite("Proof-carrying drafts")
struct ProofCarryingDraftTests {
  @Test("Transformation receipt exposes every trust boundary in order")
  func transformationReceipt() {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
    let draft = ProofCarryingDraft.transformation(
      id: id,
      instruction: "Make this concise",
      sourceText: "  This is a longer sentence.  ",
      proposedText: "  A concise sentence.  ",
      targetLabel: "Mail — reply field"
    )

    #expect(draft.id == id)
    #expect(draft.sourceText == "  This is a longer sentence.  ")
    #expect(draft.proposedText == "  A concise sentence.  ")
    #expect(draft.steps.map(\.scope) == [.onDevice, .network, .destination])
    #expect(draft.steps.map(\.id) == ["speech", "transform", "insert"])
    #expect(draft.usedNetwork)
    #expect(draft.state == .awaitingApproval)
    #expect(draft.state.isActionable)
  }

  @Test("Target failure preserves the same draft identity and text")
  func targetFailurePreservesDraft() {
    let original = ProofCarryingDraft.transformation(
      instruction: "Turn this into bullets",
      sourceText: "First. Second.",
      proposedText: "• First\n• Second",
      targetLabel: "Notes — body"
    )
    let failed = original.updating(
      state: .targetUnavailable,
      notice: "The original field changed. Nothing was inserted."
    )

    #expect(failed.id == original.id)
    #expect(failed.proposedText == original.proposedText)
    #expect(failed.steps == original.steps)
    #expect(failed.state.isActionable)
    #expect(failed.notice == "The original field changed. Nothing was inserted.")
  }

  @Test("Approved and copied receipts are terminal")
  func terminalStates() {
    #expect(ProofDraftState.approvalFailed.isActionable)
    #expect(!ProofDraftState.insertionUncertain.isActionable)
    #expect(!ProofDraftState.approved.isActionable)
    #expect(!ProofDraftState.copied.isActionable)
  }
}
