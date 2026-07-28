import AppKit
import MicAICore

@MainActor
final class GlobalHotkeyMonitor {
  typealias ActionHandler = @MainActor @Sendable (MicAIMode, HotkeyAction) -> Void

  private var monitor: Any?
  private var dictationHotkey: Hotkey
  private var commandHotkey: Hotkey?
  private var dictationMachine: HotkeyStateMachine
  private var commandMachine = HotkeyStateMachine(activationMode: .hold)
  private var dictationChordTracker = HotkeyChordTracker()
  private var commandChordTracker = HotkeyChordTracker()
  private let actionHandler: ActionHandler
  private let cancelHandler: @MainActor @Sendable () -> Void

  init(
    settings: AppSettings,
    actionHandler: @escaping ActionHandler,
    cancelHandler: @escaping @MainActor @Sendable () -> Void
  ) {
    dictationHotkey = settings.dictationHotkey
    commandHotkey = settings.commandHotkey
    dictationMachine = HotkeyStateMachine(
      activationMode: settings.dictationActivationMode
    )
    self.actionHandler = actionHandler
    self.cancelHandler = cancelHandler
  }

  func update(settings: AppSettings) {
    dictationHotkey = settings.dictationHotkey
    commandHotkey = settings.commandHotkey
    dictationMachine = HotkeyStateMachine(
      activationMode: settings.dictationActivationMode
    )
    commandMachine = HotkeyStateMachine(activationMode: .hold)
    dictationChordTracker = HotkeyChordTracker()
    commandChordTracker = HotkeyChordTracker()
  }

  func reset(mode: MicAIMode) {
    switch mode {
    case .dictation:
      dictationMachine = HotkeyStateMachine(
        activationMode: dictationMachine.activationMode
      )
      dictationChordTracker = HotkeyChordTracker()
    case .command:
      commandMachine = HotkeyStateMachine(activationMode: .hold)
      commandChordTracker = HotkeyChordTracker()
    }
  }

  func start() {
    guard monitor == nil else {
      return
    }
    monitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.keyDown, .keyUp, .flagsChanged]
    ) { [weak self] event in
      let snapshot = GlobalHotkeyEvent(event: event)
      Task { @MainActor [weak self] in
        self?.receive(snapshot)
      }
    }
  }

  func stop() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }

  private func receive(_ event: GlobalHotkeyEvent) {
    if event.kind == .keyDown, event.keyCode == 53, !event.isRepeat {
      reset(mode: .dictation)
      reset(mode: .command)
      cancelHandler()
      return
    }

    if Self.matches(
      event,
      hotkey: dictationHotkey,
      chordTracker: &dictationChordTracker
    ) {
      emit(
        machine: &dictationMachine,
        mode: .dictation,
        event: inputEvent(from: event)
      )
    } else if let commandHotkey,
      Self.matches(
        event,
        hotkey: commandHotkey,
        chordTracker: &commandChordTracker
      )
    {
      emit(
        machine: &commandMachine,
        mode: .command,
        event: inputEvent(from: event)
      )
    }
  }

  private func emit(
    machine: inout HotkeyStateMachine,
    mode: MicAIMode,
    event: HotkeyInputEvent?
  ) {
    guard let event, let action = machine.handle(event) else {
      return
    }
    actionHandler(mode, action)
  }

  private static func matches(
    _ event: GlobalHotkeyEvent,
    hotkey: Hotkey,
    chordTracker: inout HotkeyChordTracker
  ) -> Bool {
    if hotkey == .rightOption {
      return event.keyCode == hotkey.keyCode && event.kind == .flagsChanged
    }
    guard let chordEvent = event.chordEvent else {
      return false
    }
    return chordTracker.matches(chordEvent, hotkey: hotkey)
  }

  private func inputEvent(from event: GlobalHotkeyEvent) -> HotkeyInputEvent? {
    switch event.kind {
    case .keyDown:
      .pressed(isRepeat: event.isRepeat)
    case .keyUp:
      .released
    case .flagsChanged:
      event.optionDown ? .pressed(isRepeat: false) : .released
    }
  }
}

private struct GlobalHotkeyEvent: Sendable {
  enum Kind: Sendable, Equatable {
    case keyDown
    case keyUp
    case flagsChanged
  }

  let kind: Kind
  let keyCode: UInt16
  let modifiers: Set<HotkeyModifier>
  let isRepeat: Bool
  let optionDown: Bool

  var chordEvent: HotkeyChordEvent? {
    switch kind {
    case .keyDown:
      .keyDown(keyCode: keyCode, modifiers: modifiers)
    case .keyUp:
      .keyUp(keyCode: keyCode, modifiers: modifiers)
    case .flagsChanged:
      nil
    }
  }

  init(event: NSEvent) {
    switch event.type {
    case .keyDown:
      kind = .keyDown
    case .keyUp:
      kind = .keyUp
    default:
      kind = .flagsChanged
    }
    keyCode = event.keyCode
    isRepeat = event.isARepeat
    optionDown = event.modifierFlags.contains(.option)

    var modifiers: Set<HotkeyModifier> = []
    if event.modifierFlags.contains(.command) {
      modifiers.insert(.command)
    }
    if event.modifierFlags.contains(.control) {
      modifiers.insert(.control)
    }
    if event.modifierFlags.contains(.option) {
      modifiers.insert(.option)
    }
    if event.modifierFlags.contains(.shift) {
      modifiers.insert(.shift)
    }
    self.modifiers = modifiers
  }
}
