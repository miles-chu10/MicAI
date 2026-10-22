import AppKit
import MicAICore
import SwiftUI

/// Click, then press the shortcut you want.
///
/// Recording listens to this window only and swallows the key press, so the
/// shortcut being recorded does not also type into a field. Escape on its own
/// stops recording without changing anything.
struct ShortcutRecorder: View {
  @Binding var hotkey: Hotkey?
  @State private var isRecording = false
  @State private var monitor: Any?

  var body: some View {
    HStack(spacing: 6) {
      Button {
        isRecording ? stop() : start()
      } label: {
        if isRecording {
          Text("Type a shortcut…")
            .foregroundStyle(.secondary)
        } else if let hotkey {
          KeyCaps(hotkey)
        } else {
          Text("Record Shortcut")
        }
      }
      .help("Needs Control, Option or Command. Press Escape to stop recording.")
      .accessibilityLabel(accessibilityLabel)

      if hotkey != nil, !isRecording {
        Button {
          hotkey = nil
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove shortcut")
      }
    }
    .onDisappear(perform: stop)
  }

  private var accessibilityLabel: String {
    if isRecording {
      return "Recording shortcut. Press the keys now."
    }
    return hotkey.map { "Shortcut \($0.displayName). Click to change." } ?? "Record shortcut"
  }

  private func start() {
    isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let keyCode = event.keyCode
      let flags = event.modifierFlags
      // Local monitors run on the main thread.
      MainActor.assumeIsolated {
        record(keyCode: keyCode, flags: flags)
      }
      return nil
    }
  }

  private func record(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
    let modifiers = Self.modifiers(from: flags)
    if keyCode == 53, modifiers.isEmpty {
      stop()
      return
    }
    guard let recorded = Hotkey.recordable(keyCode: keyCode, modifiers: modifiers) else {
      NSSound.beep()
      return
    }
    hotkey = recorded
    stop()
  }

  private func stop() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    isRecording = false
  }

  private static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<HotkeyModifier> {
    var modifiers: Set<HotkeyModifier> = []
    if flags.contains(.command) {
      modifiers.insert(.command)
    }
    if flags.contains(.control) {
      modifiers.insert(.control)
    }
    if flags.contains(.option) {
      modifiers.insert(.option)
    }
    if flags.contains(.shift) {
      modifiers.insert(.shift)
    }
    return modifiers
  }
}
