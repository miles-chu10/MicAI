import CoreGraphics
import MicAICore

struct CGEventKeyboardSynthesizer: KeyboardSynthesizing, Sendable {
  func copy() throws {
    try postCommandKey(virtualKey: 8)
  }

  func paste() throws {
    try postCommandKey(virtualKey: 9)
  }

  private func postCommandKey(virtualKey: CGKeyCode) throws {
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

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }
}
