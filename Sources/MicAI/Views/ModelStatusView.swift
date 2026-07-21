import MicAICore
import SwiftUI

struct ModelStatusView: View {
  let state: ModelPreparationState
  let transcript: String?
  let prepare: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      switch state {
      case .notDownloaded:
        Label("Speech model not prepared", systemImage: "arrow.down.circle")
        Button("Prepare Local Model", action: prepare)
      case .preparing(let fraction, let phase):
        Text(phase)
        ProgressView(value: fraction)
      case .ready:
        Label("Speech model ready", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      case .failed(let message):
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        Button("Retry Model Preparation", action: prepare)
      }

      if let transcript, !transcript.isEmpty {
        Divider()
        Text(transcript)
          .lineLimit(4)
          .textSelection(.enabled)
      }
    }
  }
}
