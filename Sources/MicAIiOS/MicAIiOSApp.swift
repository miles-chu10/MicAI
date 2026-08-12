#if os(iOS)
  import Foundation
  import MicAICore
  import SwiftUI

  @main
  struct MicAIiOSApp: App {
    @StateObject private var session = IOSProofSession()

    var body: some Scene {
      WindowGroup {
        IOSProofReviewScreen(session: session)
          #if targetEnvironment(simulator)
            .task {
              await IOSUIEvidenceReporter.dumpIfRequested()
            }
          #endif
      }
    }
  }

  @MainActor
  final class IOSProofSession: ObservableObject {
    @Published private(set) var draft: ProofCarryingDraft
    @Published var companionText = ""

    private let fixture: String

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
      fixture = Self.fixtureName(in: arguments)
      let base = Self.baseDraft(fixture: fixture)
      if fixture == "approved" {
        companionText = base.proposedText
        draft = base.updating(
          state: .approved,
          notice:
            "Approved into the MicAI companion draft. No other app or network request was triggered."
        )
      } else if fixture == "target-unavailable" {
        draft = base.updating(
          state: .targetUnavailable,
          notice:
            "The destination changed before approval. Nothing was inserted; this draft is still recoverable."
        )
      } else if fixture == "insertion-uncertain" {
        draft = base.updating(
          state: .insertionUncertain,
          notice:
            "Paste was sent, but completion could not be proven. Check the original field before acting again; automatic retry is disabled."
        )
      } else {
        draft = base
      }
    }

    func approve() {
      if fixture == "target-unavailable" {
        draft = draft.updating(
          state: .targetUnavailable,
          notice:
            "The destination is still unavailable. Nothing was inserted; copy or keep the draft."
        )
        return
      }
      companionText = draft.proposedText
      draft = draft.updating(
        state: .approved,
        notice:
          "Approved into the MicAI companion draft. No other app or network request was triggered."
      )
    }

    func keepDraft() {
      draft = draft.updating(
        state: .targetUnavailable,
        notice: "Kept safely in this simulator session. Nothing was inserted."
      )
    }

    func reset() {
      companionText = ""
      draft = Self.baseDraft(fixture: fixture)
    }

    private static func fixtureName(in arguments: [String]) -> String {
      guard let index = arguments.firstIndex(of: "--fixture"),
        arguments.indices.contains(index + 1)
      else {
        return "primary"
      }
      return arguments[index + 1]
    }

    private static func baseDraft(fixture: String) -> ProofCarryingDraft {
      if fixture == "narrow" {
        return .transformation(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
          instruction:
            "Turn this detailed launch update into a concise, accessible message without losing the Friday-afternoon deadline",
          sourceText:
            "The cross-platform launch-readiness checklist still needs accessibility evidence, privacy review, and narrow-width verification before Friday afternoon.",
          proposedText:
            "By Friday afternoon, finish accessibility evidence, privacy review, and narrow-width verification for launch readiness.",
          targetLabel: "MicAI companion draft — launch update"
        )
      }
      return .transformation(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        instruction: "Make this concise and keep the deadline",
        sourceText:
          "Hi team, I wanted to send a quick reminder that the launch checklist is due by Friday afternoon.",
        proposedText: "Reminder: the launch checklist is due Friday afternoon.",
        targetLabel: "MicAI companion draft"
      )
    }
  }

  struct IOSProofReviewScreen: View {
    @ObservedObject var session: IOSProofSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            header
            statusStrip
            requestedChange
            proposedText
            privacyReceipt
            actions

            if session.draft.state == .approved {
              companionDraft
            }
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 20)
          .frame(maxWidth: 720, alignment: .leading)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("MicAI Proof")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          if session.draft.state == .approved {
            ToolbarItem(placement: .topBarTrailing) {
              Button("Reset", action: session.reset)
            }
          }
        }
      }
      .accessibilityIdentifier("ios.proof.screen")
    }

    @ViewBuilder
    private var header: some View {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          headerIcon
          headerText
        }
        .accessibilityElement(children: .combine)
      } else {
        HStack(alignment: .top, spacing: 14) {
          headerIcon
          headerText
        }
        .accessibilityElement(children: .combine)
      }
    }

    private var headerIcon: some View {
      Image(systemName: "checkmark.shield.fill")
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 42, height: 42)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var headerText: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text("Proof before paste")
          .font(.title2.weight(.semibold))
        Text(
          "Review the proposal, processing route, and destination before approval."
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }

    private var statusStrip: some View {
      VStack(alignment: .leading, spacing: 8) {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 8) {
            statusLabel
            routeBadge
          }
        } else {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            statusLabel
            Spacer(minLength: 8)
            routeBadge
          }
        }
        Text("Destination: \(session.draft.targetLabel)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let notice = session.draft.notice {
          Text(notice)
            .font(.subheadline)
            .foregroundStyle(statusColor)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ios.proof.notice")
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.background, in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(statusColor.opacity(0.28), lineWidth: 1)
      }
      .accessibilityElement(children: .contain)
    }

    private var statusLabel: some View {
      Label(statusTitle, systemImage: statusImage)
        .font(.headline)
        .foregroundStyle(statusColor)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var routeBadge: some View {
      Text("LOCAL + NETWORK")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var requestedChange: some View {
      GroupBox("Requested change") {
        VStack(alignment: .leading, spacing: 10) {
          Text(session.draft.instruction)
            .font(.body.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
          if let sourceText = session.draft.sourceText {
            Divider()
            Text("Selected text")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(sourceText)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    private var proposedText: some View {
      GroupBox(proposalSectionTitle) {
        Text(session.draft.proposedText)
          .font(.body)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
          .accessibilityIdentifier("ios.proof.proposal")
      }
    }

    private var privacyReceipt: some View {
      GroupBox("Privacy receipt") {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(session.draft.steps.enumerated()), id: \.element.id) {
            index,
            step in
            IOSProofStepRow(step: step)
            if index < session.draft.steps.count - 1 {
              Divider()
            }
          }
        }
        .accessibilityIdentifier("ios.proof.receipt")
      }
    }

    @ViewBuilder
    private var actions: some View {
      if session.draft.state.isActionable {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) {
            actionButtons
          }
          VStack(spacing: 10) {
            actionButtons
          }
        }
      }
    }

    @ViewBuilder
    private var actionButtons: some View {
      Button(action: session.approve) {
        Label(
          session.draft.state == .targetUnavailable ? "Retry" : "Approve",
          systemImage: "checkmark.shield"
        )
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier("ios.proof.approve")

      Button(action: session.keepDraft) {
        Label("Keep Draft", systemImage: "tray.full")
          .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .accessibilityIdentifier("ios.proof.keep")
    }

    private var companionDraft: some View {
      GroupBox("Approved companion draft") {
        TextEditor(text: $session.companionText)
          .frame(minHeight: 120)
          .scrollContentBackground(.hidden)
          .accessibilityIdentifier("ios.proof.companionDraft")
          .accessibilityLabel("Approved companion draft")
      }
    }

    private var statusTitle: String {
      switch session.draft.state {
      case .awaitingApproval:
        "Awaiting approval"
      case .targetUnavailable:
        "Destination unavailable"
      case .approvalFailed:
        "Approval did not complete"
      case .insertionUncertain:
        "Check the original field"
      case .approved:
        "Approved"
      case .copied:
        "Copied"
      }
    }

    private var proposalSectionTitle: String {
      switch session.draft.state {
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
      switch session.draft.state {
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
      switch session.draft.state {
      case .awaitingApproval:
        .orange
      case .targetUnavailable:
        .red
      case .approvalFailed:
        .orange
      case .insertionUncertain:
        .red
      case .approved:
        .green
      case .copied:
        .blue
      }
    }
  }

  private struct IOSProofStepRow: View {
    let step: ProofStep

    var body: some View {
      HStack(alignment: .top, spacing: 11) {
        Image(systemName: imageName)
          .foregroundStyle(color)
          .frame(width: 22)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline) {
            Text(step.title)
              .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(step.scope.label)
              .font(.caption2.weight(.bold))
              .foregroundStyle(color)
          }
          Text(step.detail)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 9)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(step.title), \(step.scope.label). \(step.detail)")
    }

    private var imageName: String {
      switch step.scope {
      case .onDevice:
        "iphone"
      case .network:
        "network"
      case .destination:
        "scope"
      }
    }

    private var color: Color {
      switch step.scope {
      case .onDevice:
        .green
      case .network:
        .blue
      case .destination:
        .orange
      }
    }
  }

  #if DEBUG
    struct IOSProofReviewScreen_Previews: PreviewProvider {
      static var previews: some View {
        Group {
          IOSProofReviewScreen(
            session: IOSProofSession(
              arguments: ["MicAIiOS", "--fixture", "primary"]
            )
          )
          .previewDisplayName("Primary")

          IOSProofReviewScreen(
            session: IOSProofSession(
              arguments: ["MicAIiOS", "--fixture", "target-unavailable"]
            )
          )
          .previewDisplayName("Target unavailable")

          IOSProofReviewScreen(
            session: IOSProofSession(
              arguments: ["MicAIiOS", "--fixture", "approved"]
            )
          )
          .previewDisplayName("Approved companion draft")

          IOSProofReviewScreen(
            session: IOSProofSession(
              arguments: ["MicAIiOS", "--fixture", "insertion-uncertain"]
            )
          )
          .previewDisplayName("Insertion outcome uncertain")

          IOSProofReviewScreen(
            session: IOSProofSession(
              arguments: ["MicAIiOS", "--fixture", "narrow"]
            )
          )
          .environment(\.dynamicTypeSize, .accessibility3)
          .previewDisplayName("Narrow accessibility text")
        }
      }
    }
  #endif
#else
  import Foundation

  @main
  enum MicAIiOSBuildPlaceholder {
    static func main() {
      print("MicAIiOS is an iOS-only companion target.")
    }
  }
#endif
