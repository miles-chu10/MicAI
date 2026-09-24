import MicAICore
import SwiftUI

struct RecordingHUDView: View {
  let mode: MicAIMode?
  let phase: OperationPhase
  let inputLevel: Float
  let message: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let presentation = RecordingHUDPresentation(
      mode: mode,
      phase: phase,
      message: message
    )

    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(accentColor.opacity(0.16))

        Image(systemName: presentation.modeIcon)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(accentColor)
          .symbolEffect(
            .pulse,
            isActive: phase == .recording && !reduceMotion
          )
      }
      .frame(width: 40, height: 40)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(presentation.title)
          .font(.system(size: 13, weight: .semibold))

        Text(presentation.status)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.primary.opacity(0.68))
          .lineLimit(1)
          .truncationMode(.tail)
      }

      Spacer(minLength: 8)

      if phase == .recording {
        AudioLevelBars(level: inputLevel, tint: accentColor)
          .accessibilityHidden(true)
      } else if case .failed = phase {
        Image(systemName: presentation.isCancellation ? "xmark" : "exclamationmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(accentColor)
          .frame(width: 28, height: 28)
          .accessibilityHidden(true)
      } else {
        ProgressView()
          .controlSize(.small)
          .tint(accentColor)
          .frame(width: 28, height: 28)
          .accessibilityHidden(true)
      }

      if presentation.canCancel {
        Text("esc")
          .font(.system(size: 9, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 5))
          .overlay {
            RoundedRectangle(cornerRadius: 5)
              .stroke(Color.primary.opacity(0.1), lineWidth: 1)
          }
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 12)
    .frame(width: 328, height: 72)
    .micAIHUDSurface(cornerRadius: 14)
    .shadow(color: .black.opacity(0.22), radius: 16, y: 7)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilitySummary(presentation: presentation))
  }

  private func accessibilitySummary(
    presentation: RecordingHUDPresentation
  ) -> String {
    var parts = ["MicAI \(presentation.title)", presentation.status]
    if phase == .recording {
      parts.append("input \(inputPercentage) percent")
    }
    if presentation.canCancel {
      parts.append("Press Escape to cancel")
    }
    return parts.joined(separator: ". ")
  }

  private var accentColor: Color {
    if phase == .failed(.cancelled) {
      return .secondary
    }
    if case .failed = phase {
      return MicAIStatusColor.attention
    }
    return MicAIStatusColor.modeTint(mode)
  }

  private var inputPercentage: Int {
    min(max(Int((inputLevel / 0.25) * 100), 0), 100)
  }
}

struct RecordingHUDPresentation: Equatable {
  let mode: MicAIMode?
  let phase: OperationPhase
  let message: String?

  var isCancellation: Bool {
    phase == .failed(.cancelled)
  }

  var title: String {
    if isCancellation {
      return "Cancelled"
    }
    return switch mode {
    case .command:
      "AI Command"
    case .translate:
      "AI Translate"
    case .ask:
      "Ask AI"
    case .dictation:
      "Dictating"
    case nil:
      "MicAI"
    }
  }

  var status: String {
    switch phase {
    case .idle:
      "Ready"
    case .recording:
      mode == nil || mode == .dictation ? "Listening" : "Listening for your instruction"
    case .transcribing:
      "Transcribing audio"
    case .awaitingLLM:
      "Applying your command"
    case .inserting:
      "Inserting text"
    case .failed(.cancelled):
      "Nothing was inserted"
    case .failed:
      if let message, !message.isEmpty {
        message
      } else {
        "Open MicAI for recovery options"
      }
    }
  }

  var modeIcon: String {
    switch mode {
    case .command:
      "sparkles"
    case .translate:
      "globe"
    case .ask:
      "questionmark.bubble"
    case .dictation, nil:
      "mic.fill"
    }
  }

  var canCancel: Bool {
    switch phase {
    case .recording, .transcribing, .awaitingLLM:
      true
    case .idle, .inserting, .failed:
      false
    }
  }
}

private struct AudioLevelBars: View {
  let level: Float
  let tint: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let weights: [CGFloat] = [0.58, 0.82, 1, 0.72, 0.48]

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      ForEach(weights.indices, id: \.self) { index in
        Capsule()
          .fill(tint)
          .frame(width: 3, height: barHeight(at: index))
      }
    }
    .frame(width: 30, height: 28)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: level)
  }

  private func barHeight(at index: Int) -> CGFloat {
    let normalized = min(max(CGFloat(level) / 0.25, 0), 1)
    return 5 + (normalized * 21 * weights[index])
  }
}
