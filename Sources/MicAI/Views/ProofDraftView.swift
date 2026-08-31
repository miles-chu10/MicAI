import MicAICore
import SwiftUI

struct ProofCenterView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        proofHeader

        if let draft = appModel.pendingProofDraft {
          ProofDraftPanel(
            draft: draft,
            isWorking: appModel.isResolvingProofDraft,
            approve: appModel.approveProofDraft,
            copy: appModel.copyProofDraft,
            discard: appModel.discardProofDraft
          )
        } else if let draft = appModel.lastProofDraft {
          ProofDraftPanel(draft: draft)
        } else {
          ContentUnavailableView(
            "No proof draft",
            systemImage: "checkmark.shield",
            description: Text(
              "An AI Command result appears here before MicAI can insert it."
            )
          )
        }
      }
      .padding(28)
      .frame(maxWidth: 760, alignment: .leading)
    }
    .accessibilityIdentifier("proof.center")
  }

  private var proofHeader: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "checkmark.shield.fill")
        .font(.title2)
        .foregroundStyle(.tint)
        .padding(10)
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text("Proof before paste")
          .font(.title.weight(.semibold))
        Text(
          "Review the proposed text, its processing route, and the locked destination before another app changes."
        )
        .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

struct ProofDraftPanel: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let draft: ProofCarryingDraft
  var isWorking = false
  var approve: (() -> Void)?
  var copy: (() -> Void)?
  var discard: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      statusHeader

      if let notice = draft.notice {
        Label(notice, systemImage: statusImage)
          .foregroundStyle(statusColor)
          .fixedSize(horizontal: false, vertical: true)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(statusColor.opacity(0.10), in: .rect(cornerRadius: 8))
          .accessibilityIdentifier("proof.notice")
      }

      ProofSection("Requested change") {
        VStack(alignment: .leading, spacing: 12) {
          Text("Instruction")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(draft.instruction)
            .frame(maxWidth: .infinity, alignment: .leading)
          if let sourceText = draft.sourceText, !sourceText.isEmpty {
            Divider()
            Text("Selected text")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(sourceText)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityLabel("Original selected text")
              .accessibilityValue(sourceText)
          } else {
            Label("New text at the original cursor", systemImage: "text.cursor")
              .foregroundStyle(.secondary)
          }
        }
      }

      ProofSection(proposalSectionTitle) {
        Text(draft.proposedText)
          .font(.body)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
          .accessibilityIdentifier("proof.proposal")
          .accessibilityLabel(proposalSectionTitle)
          .accessibilityValue(draft.proposedText)
      }

      ProofSection("Privacy receipt") {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
            ProofStepRow(step: step)
            if index < draft.steps.count - 1 {
              Divider()
            }
          }
        }
        .accessibilityIdentifier("proof.receipt")
      }

      if draft.state.isActionable, let approve, let copy, let discard {
        Group {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
              proofActions(approve: approve, copy: copy, discard: discard)
            }
          } else {
            HStack(spacing: 10) {
              proofActions(approve: approve, copy: copy, discard: discard)
            }
          }
        }
        .disabled(isWorking)

        if isWorking {
          ProgressView("Checking the original field…")
            .controlSize(.small)
            .accessibilityLabel("Checking the original field")
        }
      }
    }
  }

  private var statusHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: statusImage)
        .font(.title2)
        .foregroundStyle(statusColor)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(statusTitle)
          .font(.title2.weight(.semibold))
        Text("Destination: \(draft.targetLabel)")
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      Text(draft.usedNetwork ? "LOCAL + NETWORK" : "LOCAL")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .accessibilityLabel(
          draft.usedNetwork ? "Used local and network processing" : "Used local processing"
        )
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func proofActions(
    approve: @escaping () -> Void,
    copy: @escaping () -> Void,
    discard: @escaping () -> Void
  ) -> some View {
    Button(
      proofActionTitle,
      systemImage: "checkmark.shield",
      action: approve
    )
    .micAIPrimaryButtonStyle()
    .accessibilityIdentifier("proof.approve")
    .accessibilityHint(
      "Reactivates and verifies the captured field before inserting the proposed text."
    )

    Button("Copy Draft", systemImage: "doc.on.doc", action: copy)
      .micAISecondaryButtonStyle()
      .accessibilityIdentifier("proof.copy")
      .accessibilityHint("Copies the proposed text without changing the target app.")

    Button("Discard", role: .cancel, action: discard)
      .micAISecondaryButtonStyle()
      .accessibilityIdentifier("proof.discard")
      .accessibilityHint("Discards this session-only draft without inserting it.")
  }

  private var statusTitle: String {
    switch draft.state {
    case .awaitingApproval:
      "Awaiting your approval"
    case .targetUnavailable:
      "Target lock stopped insertion"
    case .approvalFailed:
      "Approval did not complete"
    case .insertionUncertain:
      "Check the original field"
    case .approved:
      "Approved and inserted"
    case .copied:
      "Copied without insertion"
    }
  }

  private var proposalSectionTitle: String {
    switch draft.state {
    case .awaitingApproval, .targetUnavailable, .approvalFailed:
      "Proposed text — not inserted"
    case .insertionUncertain:
      "Paste outcome uncertain"
    case .approved:
      "Approved text"
    case .copied:
      "Copied text"
    }
  }

  private var statusImage: String {
    switch draft.state {
    case .awaitingApproval:
      "hand.raised.fill"
    case .targetUnavailable:
      "exclamationmark.shield.fill"
    case .approvalFailed:
      "xmark.shield.fill"
    case .insertionUncertain:
      "questionmark.diamond.fill"
    case .approved:
      "checkmark.shield.fill"
    case .copied:
      "doc.on.doc.fill"
    }
  }

  private var statusColor: Color {
    switch draft.state {
    case .awaitingApproval:
      MicAIStatusColor.attention
    case .targetUnavailable:
      .red
    case .approvalFailed:
      MicAIStatusColor.attention
    case .insertionUncertain:
      MicAIStatusColor.danger
    case .approved:
      MicAIStatusColor.ready
    case .copied:
      .accentColor
    }
  }

  private var proofActionTitle: String {
    switch draft.state {
    case .targetUnavailable:
      "Retry Original Field"
    case .approvalFailed:
      "Retry Approval"
    case .awaitingApproval, .insertionUncertain, .approved, .copied:
      "Approve Original Field"
    }
  }
}

private struct ProofSection<Content: View>: View {
  let title: String
  private let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.38), in: .rect(cornerRadius: 10))
    .accessibilityElement(children: .contain)
  }
}

private struct ProofStepRow: View {
  let step: ProofStep

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: imageName)
        .foregroundStyle(color)
        .frame(width: 22)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline) {
          Text(step.title)
            .font(.body.weight(.medium))
          Spacer()
          Text(step.scope.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
        }
        Text(step.detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(step.title), \(step.scope.label). \(step.detail)")
  }

  private var imageName: String {
    switch step.scope {
    case .onDevice:
      "laptopcomputer"
    case .network:
      "network"
    case .destination:
      "scope"
    }
  }

  private var color: Color {
    switch step.scope {
    case .onDevice:
      MicAIStatusColor.ready
    case .network:
      .blue
    case .destination:
      MicAIStatusColor.attention
    }
  }
}

#if DEBUG
  extension ProofCarryingDraft {
    fileprivate static let previewAwaiting = ProofCarryingDraft.transformation(
      instruction: "Make this concise and keep the deadline",
      sourceText:
        "Hi team, I wanted to send a quick reminder that the launch checklist is due by Friday afternoon.",
      proposedText: "Reminder: the launch checklist is due Friday afternoon.",
      targetLabel: "Mail — reply field"
    )

    fileprivate static let previewUnavailable = previewAwaiting.updating(
      state: .targetUnavailable,
      notice: "The target lock stopped insertion. The draft remains safe in this session."
    )
  }

  struct ProofDraftView_Previews: PreviewProvider {
    static var previews: some View {
      Group {
        ProofDraftPanel(
          draft: .previewAwaiting,
          approve: {},
          copy: {},
          discard: {}
        )
        .padding()
        .frame(width: 700, height: 780)
        .previewDisplayName("Awaiting approval")

        ProofDraftPanel(
          draft: .previewUnavailable,
          approve: {},
          copy: {},
          discard: {}
        )
        .padding()
        .frame(width: 520, height: 820)
        .previewDisplayName("Target unavailable")
      }
    }
  }
#endif
