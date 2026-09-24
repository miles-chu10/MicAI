import MicAICore
import SwiftUI

struct ModelStatusView: View {
  let state: ModelPreparationState
  let transcript: String?
  let prepare: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      switch state {
      case .notDownloaded:
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Label("Speech model not prepared", systemImage: "arrow.down.circle")
          Spacer()
          Button("Prepare Local Model", action: prepare)
        }
      case .preparing(let fraction, let phase):
        Label(phase, systemImage: "arrow.down.circle.fill")
          .foregroundStyle(.secondary)
        ProgressView(value: fraction)
          .accessibilityLabel("Speech model preparation")
          .accessibilityValue("\(Int(fraction * 100)) percent")
      case .ready:
        Label {
          Text("Speech model ready")
        } icon: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(MicAIStatusColor.ready)
        }
      case .failed(let message):
        Label {
          Text(message)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(MicAIStatusColor.danger)
        }
        Button("Retry Model Preparation", action: prepare)
      }

      if let transcript, !transcript.isEmpty {
        Divider()
        Text("Most recent local result")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(transcript)
          .lineLimit(4)
          .textSelection(.enabled)
      }
    }
  }
}
