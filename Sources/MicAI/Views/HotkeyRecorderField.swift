import AppKit
import MicAICore
import SwiftUI

/// Click, then press the shortcut. Escape stops recording without changing
/// anything; the rules for what is accepted live in `HotkeyCapture`.
struct HotkeyRecorderField: View {
  let title: String
  @Binding var hotkey: Hotkey?
  var allowsNone = true

  @State private var isRecording = false
  @State private var rejection: String?
  @State private var monitor: Any?

  var body: some View {
    LabeledContent(title) {
      VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: 6) {
          Button {
            isRecording ? stopRecording() : startRecording()
          } label: {
            Text(buttonTitle)
              .monospacedDigit()
              .frame(minWidth: 120)
          }
          .micAISecondaryButtonStyle()
          .accessibilityHint(
            isRecording
              ? "Press the new shortcut, or Escape to keep the current one."
              : "Records a new shortcut."
          )

          if allowsNone, hotkey != nil, !isRecording {
            Button("Clear", systemImage: "xmark.circle.fill") {
              hotkey = nil
              rejection = nil
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Turn this shortcut off")
          }
        }
        if let rejection {
          Text(rejection)
            .font(.caption)
            .foregroundStyle(MicAIStatusColor.attention)
        }
      }
    }
    .onDisappear(perform: stopRecording)
  }

  private var buttonTitle: String {
    if isRecording {
      return "Press shortcut…"
    }
    return hotkey?.displayName ?? "Not set"
  }

  private func startRecording() {
    rejection = nil
    isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
      handle(event)
      return nil
    }
  }

  private func stopRecording() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    isRecording = false
  }

  private func handle(_ event: NSEvent) {
    if event.type == .flagsChanged {
      // Only Right Option is bindable on its own; every other modifier is
      // waiting for the key it will be combined with.
      guard event.keyCode == HotkeyCapture.rightOptionKeyCode,
        event.modifierFlags.contains(.option)
      else {
        return
      }
    } else if event.keyCode == HotkeyCapture.escapeKeyCode,
      Self.modifiers(of: event).isEmpty
    {
      stopRecording()
      return
    }

    switch HotkeyCapture.resolve(keyCode: event.keyCode, modifiers: Self.modifiers(of: event)) {
    case .success(let captured):
      hotkey = captured
      rejection = nil
      stopRecording()
    case .failure(let error):
      rejection = error.localizedDescription
    }
  }

  private static func modifiers(of event: NSEvent) -> Set<HotkeyModifier> {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var result: Set<HotkeyModifier> = []
    if flags.contains(.command) { result.insert(.command) }
    if flags.contains(.control) { result.insert(.control) }
    if flags.contains(.option) { result.insert(.option) }
    if flags.contains(.shift) { result.insert(.shift) }
    return result
  }
}
