import AppKit
import MicAICore

@MainActor
final class GlobalHotkeyMonitor {
  typealias ActionHandler = @MainActor @Sendable (MicAIMode, HotkeyAction) -> Void

  private var monitor: Any?
  private var dictationHotkey: Hotkey
  private var commandHotkey: Hotkey?
  private var dictationMachine: HotkeyStateMachine
  private var commandMachine = HotkeyStateMachine(activationMode: .toggle)
  private let actionHandler: ActionHandler

  init(settings: AppSettings, actionHandler: @escaping ActionHandler) {
    dictationHotkey = settings.dictationHotkey
    commandHotkey = settings.commandHotkey
    dictationMachine = HotkeyStateMachine(
      activationMode: settings.dictationActivationMode
    )
    self.actionHandler = actionHandler
  }

  func update(settings: AppSettings) {
    dictationHotkey = settings.dictationHotkey
    commandHotkey = settings.commandHotkey
    dictationMachine = HotkeyStateMachine(
      activationMode: settings.dictationActivationMode
    )
    commandMachine = HotkeyStateMachine(activationMode: .toggle)
  }

  func reset(mode: MicAIMode) {
    switch mode {
    case .dictation:
      dictationMachine = HotkeyStateMachine(
        activationMode: dictationMachine.activationMode
      )
    case .command:
      commandMachine = HotkeyStateMachine(activationMode: .toggle)
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
      emit(machine: &dictationMachine, mode: .dictation, event: .cancel)
      emit(machine: &commandMachine, mode: .command, event: .cancel)
      return
    }

    if matches(event, hotkey: dictationHotkey) {
      emit(
        machine: &dictationMachine,
        mode: .dictation,
        event: inputEvent(from: event)
      )
    } else if let commandHotkey, matches(event, hotkey: commandHotkey) {
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

  private func matches(_ event: GlobalHotkeyEvent, hotkey: Hotkey) -> Bool {
    guard event.keyCode == hotkey.keyCode else {
      return false
    }
    if hotkey == .rightOption {
      return event.kind == .flagsChanged
    }
    return event.kind != .flagsChanged && event.modifiers == hotkey.modifiers
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
