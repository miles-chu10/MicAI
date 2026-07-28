import MicAICore
import SwiftUI

struct RecordingHUDView: View {
  let phase: OperationPhase
  let inputLevel: Float
  let message: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: phase.systemImage)
        .font(.title2)
        .foregroundStyle(phase.tint)
        .symbolEffect(
          .pulse,
          isActive: phase == .recording && !reduceMotion
        )
        .frame(width: 36)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 7) {
        Text(phase.displayName)
          .font(.headline)

        if phase == .recording {
          ProgressView(value: inputLevel, total: 0.25)
            .progressViewStyle(.linear)
            .tint(.red)
            .accessibilityLabel("Microphone input level")
            .accessibilityValue("\(inputPercentage) percent")
        } else if case .failed = phase {
          Text(message ?? "Open MicAI for recovery options.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
          ProgressView()
            .controlSize(.small)
        }
      }

      Spacer()

      Label("Escape to cancel", systemImage: "escape")
        .font(.callout)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .opacity(canCancel ? 1 : 0)
        .accessibilityHidden(!canCancel)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .frame(width: 360, height: 104)
    .background(.regularMaterial, in: .rect(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(.separator, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }

  private var canCancel: Bool {
    switch phase {
    case .recording, .transcribing, .awaitingLLM:
      true
    case .idle, .inserting, .failed:
      false
    }
  }

  private var inputPercentage: Int {
    min(max(Int((inputLevel / 0.25) * 100), 0), 100)
  }
}
