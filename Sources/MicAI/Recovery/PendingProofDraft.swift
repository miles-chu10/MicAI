import MicAICore

struct PendingProofDraftContext {
  let draft: ProofCarryingDraft
  let intent: InsertionIntent
  let target: TargetIdentity
  let fixtureFailure: MicAIError?

  func matchesCurrentSelection(_ currentSelection: String?) -> Bool {
    switch intent {
    case .insert:
      true
    case .replaceSelection:
      currentSelection == draft.sourceText
    }
  }
}
