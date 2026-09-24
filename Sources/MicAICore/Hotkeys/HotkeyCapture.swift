import Foundation

public enum HotkeyCaptureError: Error, Equatable, Sendable {
  /// Escape is the global cancel key, so binding it would make cancelling
  /// start a new operation.
  case reservedKey
  /// A bare letter or number would fire on ordinary typing.
  case needsModifier
}

extension HotkeyCaptureError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .reservedKey:
      "Escape is reserved for cancelling."
    case .needsModifier:
      "Add ⌘, ⌃, ⌥ or ⇧ so the shortcut doesn't fire while typing."
    }
  }
}

/// Turns one key press recorded in Settings into a `Hotkey`.
///
/// Kept free of AppKit so the rules are testable: the recorder view only
/// translates `NSEvent` into a key code and modifier set.
public enum HotkeyCapture {
  public static let escapeKeyCode: UInt16 = 53
  public static let rightOptionKeyCode: UInt16 = 61

  /// Function keys are safe on their own: nobody types them into a document.
  static let standaloneKeyCodes: Set<UInt16> = [
    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
  ]

  public static func resolve(
    keyCode: UInt16,
    modifiers: Set<HotkeyModifier>
  ) -> Result<Hotkey, HotkeyCaptureError> {
    if keyCode == escapeKeyCode {
      return .failure(.reservedKey)
    }
    if keyCode == rightOptionKeyCode {
      return .success(.rightOption)
    }
    if modifiers.isEmpty, !standaloneKeyCodes.contains(keyCode) {
      return .failure(.needsModifier)
    }
    return .success(Hotkey(keyCode: keyCode, modifiers: modifiers))
  }
}
