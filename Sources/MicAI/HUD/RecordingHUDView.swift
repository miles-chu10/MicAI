import MicAICore
import SwiftUI

/// The floating pill shown while MicAI works.
///
/// It answers two questions at a glance: which mode is running, and whether
/// your words are still on this Mac or have gone to the model. It is always
/// dark, like the system's own volume and brightness HUDs, so it reads the same
/// over a white document and a dark terminal.
struct RecordingHUDView: View {
  @ObservedObject var model: HUDModel

  /// The panel is this size whatever the content, so live text can grow and
  /// shrink without resizing a window on every word. The panel ignores the
  /// mouse, so the empty space around the pill blocks nothing.
  static let panelSize = CGSize(width: 560, height: 170)

  var body: some View {
    VStack(spacing: 8) {
      if model.phase == .recording, let partial = model.partialText, !partial.isEmpty {
        LiveText(text: partial)
          .transition(.opacity)
      }
      pill
    }
    .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .bottom)
    .environment(\.colorScheme, .dark)
    .animation(.snappy(duration: 0.2), value: model.phase)
    .animation(.easeOut(duration: 0.15), value: model.partialText)
  }

  private var pill: some View {
    HStack(spacing: 12) {
      glyph
      content
      if showsEscape {
        Text("esc")
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .overlay {
            RoundedRectangle(cornerRadius: 4)
              .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
          }
          .accessibilityLabel("Press Escape to cancel")
      }
    }
    .padding(.leading, 8)
    .padding(.trailing, 16)
    .frame(height: 52)
    .background(.ultraThinMaterial, in: .capsule)
    .background(Color.black.opacity(0.55), in: .capsule)
    .overlay {
      Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
    }
    .padding(12)
    .fixedSize()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityText)
  }

  private var glyph: some View {
    ZStack {
      Circle()
        .fill(glyphColor.opacity(0.18))
      Image(systemName: glyphSymbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(glyphColor)
        .symbolEffect(.pulse, isActive: model.phase == .transcribing)
    }
    .frame(width: 36, height: 36)
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .recording:
      HStack(spacing: 12) {
        Waveform(levels: model.levels, color: model.mode.hudTint)
        TimelineView(.periodic(from: model.recordingStartedAt, by: 1)) { context in
          Text(elapsed(until: context.date))
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        if let tag = recordingTag {
          Divider().frame(height: 18)
          Text(tag)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
    case .transcribing:
      twoLine("Transcribing", "On this Mac")
    case .awaitingLLM:
      twoLine(awaitingTitle, awaitingDetail)
    case .inserting:
      twoLine("Inserting", "Your clipboard comes back afterwards")
    case .failed:
      twoLine(failureTitle, model.message ?? "Open MicAI for recovery options.")
        .frame(maxWidth: 300, alignment: .leading)
    case .idle:
      EmptyView()
    }
  }

  private func twoLine(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
      Text(detail)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
  }

  // MARK: - Derived values

  private var glyphSymbol: String {
    switch model.phase {
    case .recording:
      model.isHandsFree ? "hand.raised.fill" : model.mode.symbol
    case .transcribing:
      "laptopcomputer"
    case .awaitingLLM:
      model.polishesOnDevice && model.mode == .dictation ? "laptopcomputer" : "cloud.fill"
    case .inserting:
      "checkmark"
    case .failed:
      "exclamationmark.triangle.fill"
    case .idle:
      model.mode.symbol
    }
  }

  private var glyphColor: Color {
    switch model.phase {
    case .recording:
      model.mode.hudTint
    case .inserting:
      .green
    case .failed:
      .red
    case .transcribing, .awaitingLLM, .idle:
      .white
    }
  }

  private var recordingTag: String? {
    if model.isHandsFree {
      return "Hands-free"
    }
    return model.detail
  }

  private var awaitingTitle: String {
    switch model.mode {
    case .dictation:
      "Polishing"
    case .command:
      "Rewriting"
    case .translate:
      "Translating"
    case .ask:
      "Thinking"
    case .custom:
      "Working"
    }
  }

  private var awaitingDetail: String {
    var place = "sent to \(model.providerName)"
    if model.polishesOnDevice, model.mode == .dictation {
      place = "on this Mac"
    }
    if let detail = model.detail, model.mode == .dictation {
      return "\(detail) · \(place)"
    }
    return place.prefix(1).uppercased() + place.dropFirst()
  }

  private var failureTitle: String {
    model.message == nil ? "Something went wrong" : "Couldn’t finish"
  }

  /// Escape cancels up to the moment of pasting. Showing the hint once
  /// cancelling is no longer possible would be a lie.
  private var showsEscape: Bool {
    switch model.phase {
    case .recording, .transcribing, .awaitingLLM:
      true
    case .inserting, .failed, .idle:
      false
    }
  }

  private var accessibilityText: String {
    switch model.phase {
    case .recording:
      "\(model.mode.shortName) recording\(model.isHandsFree ? ", hands-free" : "")"
    case .transcribing:
      "Transcribing on this Mac"
    case .awaitingLLM:
      "\(awaitingTitle), sent to \(model.providerName)"
    case .inserting:
      "Inserting"
    case .failed:
      model.message ?? "Something went wrong"
    case .idle:
      "Ready"
    }
  }

  private func elapsed(until date: Date) -> String {
    let seconds = max(0, Int(date.timeIntervalSince(model.recordingStartedAt)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

/// The live transcript above the pill. Newest words win: a long dictation
/// shows its end, which is what you are checking as you speak.
private struct LiveText: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 13))
      .lineLimit(2)
      .truncationMode(.head)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
      .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 14))
      .overlay {
        RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
      }
      .frame(maxWidth: 480)
      .accessibilityLabel("Heard so far: \(text)")
  }
}

/// Recent input levels as vertical bars, newest on the right.
private struct Waveform: View {
  let levels: [Float]
  let color: Color

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
        Capsule()
          .fill(color)
          .frame(width: 3, height: height(for: level))
      }
    }
    .frame(height: 28)
    .animation(.linear(duration: 0.08), value: levels)
    .accessibilityHidden(true)
  }

  /// Microphone levels are small and bunched near zero; a square root spreads
  /// quiet speech into visible movement without letting loud speech clip.
  private func height(for level: Float) -> CGFloat {
    let normalized = min(max(Double(level) / 0.25, 0), 1)
    return 4 + 24 * CGFloat(normalized.squareRoot())
  }
}
