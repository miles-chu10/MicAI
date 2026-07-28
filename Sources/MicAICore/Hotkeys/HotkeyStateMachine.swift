public enum HotkeyInputEvent: Sendable, Equatable {
  case pressed(isRepeat: Bool)
  case released
  case cancel
}

public enum HotkeyAction: Sendable, Equatable {
  case startRecording
  case stopRecording
  case cancelRecording
}

public enum HotkeyChordEvent: Sendable, Equatable {
  case keyDown(keyCode: UInt16, modifiers: Set<HotkeyModifier>)
  case keyUp(keyCode: UInt16, modifiers: Set<HotkeyModifier>)
}

public struct HotkeyChordTracker: Sendable {
  private var activeKeyCode: UInt16?

  public init() {}

  public mutating func matches(_ event: HotkeyChordEvent, hotkey: Hotkey) -> Bool {
    switch event {
    case .keyDown(let keyCode, let modifiers):
      guard keyCode == hotkey.keyCode, modifiers == hotkey.modifiers else {
        return false
      }
      activeKeyCode = keyCode
      return true
    case .keyUp(let keyCode, _):
      guard activeKeyCode == keyCode, hotkey.keyCode == keyCode else {
        return false
      }
      activeKeyCode = nil
      return true
    }
  }
}

public struct HotkeyStateMachine: Sendable {
  public private(set) var isRecording = false
  public var activationMode: DictationActivationMode

  public init(activationMode: DictationActivationMode) {
    self.activationMode = activationMode
  }

  public mutating func handle(_ event: HotkeyInputEvent) -> HotkeyAction? {
    switch event {
    case .pressed(let isRepeat):
      guard !isRepeat else {
        return nil
      }
      switch activationMode {
      case .hold:
        guard !isRecording else {
          return nil
        }
        isRecording = true
        return .startRecording
      case .toggle:
        isRecording.toggle()
        return isRecording ? .startRecording : .stopRecording
      }
    case .released:
      guard activationMode == .hold, isRecording else {
        return nil
      }
      isRecording = false
      return .stopRecording
    case .cancel:
      guard isRecording else {
        return nil
      }
      isRecording = false
      return .cancelRecording
    }
  }
}
