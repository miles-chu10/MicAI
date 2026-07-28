import MicAICore
import SwiftUI

extension OperationPhase {
  var displayName: String {
    switch self {
    case .idle:
      "Idle"
    case .recording:
      "Recording"
    case .transcribing:
      "Transcribing"
    case .awaitingLLM:
      "Waiting for ChatGPT"
    case .inserting:
      "Inserting"
    case .failed:
      "Needs attention"
    }
  }

  var systemImage: String {
    switch self {
    case .idle:
      "circle.fill"
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
      .secondary
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
    HStack(spacing: 6) {
      Circle()
        .fill(phase.tint)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)

      Text(phase.displayName)
        .foregroundStyle(.secondary)
    }
    .font(.callout)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.quaternary, in: .capsule)
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("MicAI operation: \(phase.displayName)")
    .help("Current MicAI operation: \(phase.displayName)")
  }
}
