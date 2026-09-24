public enum HotkeyInputEvent: Sendable, Equatable {
  case pressed(isRepeat: Bool)
  case released
  case cancel
}

public enum HotkeyAction: Sendable, Equatable {
  case startRecording
  case stopRecording
  case cancelRecording
  /// A quick tap in `.hybrid` mode: recording carries on hands-free until the
  /// next press. Reported so the HUD can say so; nothing needs to start or stop.
  case lockRecording
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
  /// A press released sooner than this is a tap, not a hold. Long enough to
  /// forgive a slow finger, short enough that nobody holds a key this briefly
  /// on purpose to say something.
  public static let tapThreshold: TimeInterval = 0.3

  public private(set) var isRecording = false
  /// True once a `.hybrid` tap has handed recording over to hands-free.
  public private(set) var isLocked = false
  public var activationMode: DictationActivationMode
  private var pressedAt: TimeInterval = 0

  public init(activationMode: DictationActivationMode) {
    self.activationMode = activationMode
  }

  /// `time` is only read in `.hybrid` mode, to tell a tap from a hold. Any
  /// monotonic clock works; the monitor passes the event's own timestamp.
  public mutating func handle(
    _ event: HotkeyInputEvent,
    at time: TimeInterval = 0
  ) -> HotkeyAction? {
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
      case .hybrid:
        if isRecording {
          guard isLocked else {
            return nil
          }
          isRecording = false
          isLocked = false
          return .stopRecording
        }
        isRecording = true
        isLocked = false
        pressedAt = time
        return .startRecording
      }
    case .released:
      guard isRecording else {
        return nil
      }
      switch activationMode {
      case .hold:
        isRecording = false
        return .stopRecording
      case .toggle:
        return nil
      case .hybrid:
        guard !isLocked else {
          return nil
        }
        if time - pressedAt < Self.tapThreshold {
          isLocked = true
          return .lockRecording
        }
        isRecording = false
        return .stopRecording
      }
    case .cancel:
      guard isRecording else {
        return nil
      }
      isRecording = false
      isLocked = false
      return .cancelRecording
    }
  }
}
