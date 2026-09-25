import MicAICore
import SwiftUI

// The visual system in one place.
//
// The app shell is plain macOS: system materials, grouped forms, semantic
// colours, SF Symbols, so it follows light and dark mode and the user's accent
// colour like any Apple app. Colour carries exactly one meaning on top of that:
// which mode you are in. Dictation is the neutral one because it is the one you
// use all day; the AI modes and custom modes get a hue each, and the same hue
// marks that mode in the HUD, the shortcut list, History and the menu. Status is
// the only other use of colour: green for ready, red for blocked or failed, and
// neither is ever a mode's hue.

extension MicAIMode {
  var tint: Color {
    switch self {
    case .dictation:
      .primary
    case .command:
      .orange
    case .translate:
      .blue
    case .ask:
      .purple
    case .custom:
      .teal
    }
  }

  /// The HUD is always dark, so dictation needs a concrete light colour there
  /// rather than `.primary`, which would follow the system appearance.
  var hudTint: Color {
    switch self {
    case .dictation:
      Color(red: 0.95, green: 0.94, blue: 0.90)
    case .command, .translate, .ask, .custom:
      tint
    }
  }

  var symbol: String {
    switch self {
    case .dictation:
      "mic.fill"
    case .command:
      "wand.and.stars"
    case .translate:
      "character.bubble"
    case .ask:
      "questionmark.bubble"
    case .custom:
      "sparkles"
    }
  }

  var shortName: String {
    switch self {
    case .dictation:
      "Dictation"
    case .command:
      "Command"
    case .translate:
      "Translate"
    case .ask:
      "Ask AI"
    case .custom:
      "Custom"
    }
  }

  var summary: String {
    switch self {
    case .dictation:
      "Speak, and polished text lands at your cursor."
    case .command:
      "Select text and say how to change it."
    case .translate:
      "Translate a selection, or what you say."
    case .ask:
      "Questions open a window. Anything else is typed."
    case .custom:
      "Your own instructions, on their own shortcut."
    }
  }
}

/// A small filled circle in a mode's colour.
struct ModeDot: View {
  let mode: MicAIMode
  var size: CGFloat = 8

  var body: some View {
    Circle()
      .fill(mode.tint)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

/// One keycap per physical key, the way macOS prints shortcuts in menus.
struct KeyCaps: View {
  let keys: [String]
  var font: Font = .system(size: 11, weight: .medium, design: .rounded)

  init(_ hotkey: Hotkey, font: Font = .system(size: 11, weight: .medium, design: .rounded)) {
    keys = hotkey.keyCaps
    self.font = font
  }

  init(keys: [String]) {
    self.keys = keys
  }

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
        Text(key)
          .font(font)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .frame(minWidth: 20)
          .background(.quaternary, in: .rect(cornerRadius: 5))
          .overlay {
            RoundedRectangle(cornerRadius: 5)
              .strokeBorder(.separator, lineWidth: 0.5)
          }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(keys.joined(separator: " "))
  }
}

/// A capsule label for where something happens: "On this Mac", "Sent to…".
struct PlaceLabel: View {
  let onDevice: Bool
  let text: String

  var body: some View {
    Label(text, systemImage: onDevice ? "laptopcomputer" : "cloud")
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}

/// A status row whose icon and colour say ready or not, with a fix button.
struct ReadinessRow: View {
  let title: String
  let ready: Bool
  let readyText: String
  let blockedText: String
  var fixTitle: String = "Fix…"
  var fix: (() -> Void)?

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 8) {
        Label(
          ready ? readyText : blockedText,
          systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .foregroundStyle(ready ? Color.green : Color.red)
        if !ready, let fix {
          Button(fixTitle, action: fix)
            .controlSize(.small)
        }
      }
    }
  }
}
