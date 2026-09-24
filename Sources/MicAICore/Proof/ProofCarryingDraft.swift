import Foundation

public enum ProofDraftState: String, Sendable, Equatable {
  case awaitingApproval
  case targetUnavailable
  case approvalFailed
  case insertionUncertain
  case approved
  case copied

  public var isActionable: Bool {
    self == .awaitingApproval || self == .targetUnavailable || self == .approvalFailed
  }
}

public enum ProofStepScope: String, Sendable, Equatable {
  case onDevice
  case network
  case destination

  public var label: String {
    switch self {
    case .onDevice:
      "On device"
    case .network:
      "Network"
    case .destination:
      "Target locked"
    }
  }
}

public struct ProofStep: Identifiable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let detail: String
  public let scope: ProofStepScope

  public init(
    id: String,
    title: String,
    detail: String,
    scope: ProofStepScope
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.scope = scope
  }
}

public struct ProofCarryingDraft: Identifiable, Sendable, Equatable {
  public let id: UUID
  public let instruction: String
  public let sourceText: String?
  public let proposedText: String
  public let targetLabel: String
  public let steps: [ProofStep]
  public let state: ProofDraftState
  public let notice: String?

  public init(
    id: UUID = UUID(),
    instruction: String,
    sourceText: String?,
    proposedText: String,
    targetLabel: String,
    steps: [ProofStep],
    state: ProofDraftState = .awaitingApproval,
    notice: String? = nil
  ) {
    self.id = id
    self.instruction = instruction
    self.sourceText = sourceText
    self.proposedText = proposedText
    self.targetLabel = targetLabel
    self.steps = steps
    self.state = state
    self.notice = notice
  }

  public static func transformation(
    id: UUID = UUID(),
    instruction: String,
    sourceText: String?,
    proposedText: String,
    targetLabel: String,
    speechModel: String = "Parakeet TDT v2",
    transformationProvider: String = "ChatGPT personal route"
  ) -> Self {
    Self(
      id: id,
      instruction: instruction,
      sourceText: sourceText,
      proposedText: proposedText,
      targetLabel: targetLabel,
      steps: [
        ProofStep(
          id: "speech",
          title: "Command speech",
          detail: "Transcribed locally with \(speechModel).",
          scope: .onDevice
        ),
        ProofStep(
          id: "transform",
          title: "Text transformation",
          detail: "Instruction and selected text were sent through \(transformationProvider).",
          scope: .network
        ),
        ProofStep(
          id: "insert",
          title: "Insertion",
          detail: "Withheld until approval, then limited to \(targetLabel).",
          scope: .destination
        ),
      ]
    )
  }

  public var usedNetwork: Bool {
    steps.contains { $0.scope == .network }
  }

  public func updating(
    state: ProofDraftState,
    notice: String?
  ) -> Self {
    Self(
      id: id,
      instruction: instruction,
      sourceText: sourceText,
      proposedText: proposedText,
      targetLabel: targetLabel,
      steps: steps,
      state: state,
      notice: notice
    )
  }
}
