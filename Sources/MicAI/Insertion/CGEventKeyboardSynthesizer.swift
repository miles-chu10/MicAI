import CoreGraphics
import MicAICore

struct CGEventKeyboardSynthesizer: KeyboardSynthesizing, Sendable {
  func copy() throws {
    try postKey(virtualKey: 8, flags: .maskCommand)
  }

  func paste() throws {
    try postKey(virtualKey: 9, flags: .maskCommand)
  }

  /// Right Arrow with no modifiers: in a text view this collapses a selection
  /// to its end without editing anything. The flags are set explicitly so a
  /// shortcut the user is still holding cannot turn it into ⌥→ or ⌘→.
  func collapseSelectionToEnd() throws {
    try postKey(virtualKey: 124, flags: [])
  }

  private func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    guard
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: virtualKey,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: virtualKey,
        keyDown: false
      )
    else {
      throw MicAIError.insertionFailed
    }

    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }
}
