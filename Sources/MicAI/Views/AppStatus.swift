import MicAICore
import SwiftUI

extension OperationPhase {
  var displayName: String {
    switch self {
    case .idle:
      "Ready"
    case .recording:
      "Recording"
    case .transcribing:
      "Transcribing"
    case .awaitingLLM:
      "Waiting for AI"
    case .inserting:
      "Inserting"
    case .failed:
      "Needs attention"
    }
  }

  var systemImage: String {
    switch self {
    case .idle:
      "checkmark.circle.fill"
    case .recording:
      "waveform.circle.fill"
    case .transcribing:
      "text.bubble.fill"
    case .awaitingLLM:
      "sparkles"
    case .inserting:
      "arrow.down.doc.fill"
    case .failed:
      "exclamationmark.triangle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .idle:
      .green
    case .recording:
      .red
    case .transcribing, .awaitingLLM, .inserting:
      .accentColor
    case .failed:
      .orange
    }
  }
}

struct StatusPill: View {
  let phase: OperationPhase

  var body: some View {
    Label(phase.displayName, systemImage: phase.systemImage)
      .font(.callout.weight(.medium))
      .foregroundStyle(phase.tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(phase.tint.opacity(0.12), in: .capsule)
      .accessibilityLabel("MicAI status: \(phase.displayName)")
  }
}
