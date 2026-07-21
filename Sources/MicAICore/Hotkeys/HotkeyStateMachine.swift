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
