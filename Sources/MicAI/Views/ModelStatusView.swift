import MicAICore
import SwiftUI

/// The on-device speech model's state, with the action that moves it forward.
struct ModelStatusView: View {
  let state: ModelPreparationState
  let prepare: () -> Void

  var body: some View {
    switch state {
    case .notDownloaded:
      HStack {
        Text("Not downloaded")
          .foregroundStyle(.secondary)
        Button("Download", action: prepare)
      }
    case .preparing(let fraction, let phase):
      HStack {
        ProgressView(value: fraction)
          .frame(width: 120)
        Text(phase)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .ready:
      Label("Ready, on this Mac", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed(let message):
      HStack {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        Button("Retry", action: prepare)
      }
    }
  }
}
