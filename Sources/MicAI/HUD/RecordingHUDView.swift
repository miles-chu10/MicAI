import MicAICore
import SwiftUI

struct RecordingHUDView: View {
  let phase: OperationPhase
  let inputLevel: Float
  let message: String?

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: phase.systemImage)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(phase.tint)
        .symbolEffect(.pulse, isActive: phase == .recording)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 7) {
        Text(phase.displayName)
          .font(.headline)

        if phase == .recording {
          ProgressView(value: inputLevel, total: 0.25)
            .progressViewStyle(.linear)
            .tint(.red)
            .accessibilityLabel("Microphone input level")
        } else if case .failed = phase {
          Text(message ?? "Open MicAI for recovery options.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
          ProgressView()
            .controlSize(.small)
        }
      }

      Spacer()

      Text("Esc to cancel")
        .font(.caption)
        .foregroundStyle(.secondary)
        .opacity(phase == .inserting ? 0 : 1)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .frame(width: 360, height: 104)
    .background(.regularMaterial, in: .rect(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}
