import SwiftUI

struct RecoveryResultView: View {
  @ObservedObject var appModel: AppModel
  let recovery: RecoverableInsertion

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        Label(
          "Your result is safe in this session",
          systemImage: "text.badge.checkmark"
        )
        .font(.headline)
        .accessibilityAddTraits(.isHeader)

        Text(recovery.failure.localizedDescription)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Recovery reason: \(recovery.failure.localizedDescription)")

        ScrollView {
          Text(recovery.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved result text")
        .accessibilityValue(recovery.text)

        MicAIActionCluster {
          HStack {
            Button("Retry Original Field") {
              appModel.retryRecoverableInsertion()
            }
            .micAIPrimaryButtonStyle()
            .accessibilityHint(
              "Returns focus to the original app and field, then pastes the saved result."
            )

            Button("Copy Result") {
              appModel.copyRecoverableResult()
            }
            .micAISecondaryButtonStyle()
            .accessibilityHint("Replaces the current clipboard with the saved result.")

            Spacer()

            Button("Dismiss", role: .cancel) {
              appModel.dismissRecoverableInsertion()
            }
            .micAISecondaryButtonStyle()
            .accessibilityHint("Discards the saved result so a new recording can start.")
          }
        }
        .disabled(appModel.isRecoveringInsertion)

        if appModel.isRecoveringInsertion {
          ProgressView("Retrying insertion…")
            .controlSize(.small)
            .accessibilityLabel("Retrying insertion")
        }

        Text(
          "Retry returns to the exact app and focused field captured before recording. Copy Result intentionally replaces the current clipboard."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Insertion recovery", systemImage: "arrow.uturn.backward.circle")
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Insertion recovery")
  }
}
