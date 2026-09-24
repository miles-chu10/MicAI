import AppKit
import MicAICore

@MainActor
final class GlobalHotkeyMonitor {
  typealias ActionHandler = @MainActor @Sendable (MicAIMode, HotkeyAction) -> Void

  // One machine and chord tracker per mode, keyed rather than four sets of
  // fields: adding AI Translate and Ask AI to a hardcoded pair meant every
  // method growing a branch it could silently forget.
  private struct Binding {
    var hotkey: Hotkey
    var machine: HotkeyStateMachine
    var chordTracker = HotkeyChordTracker()
  }

  private var monitor: Any?
  private var bindings: [MicAIMode: Binding] = [:]
  private let actionHandler: ActionHandler
  private let cancelHandler: @MainActor @Sendable () -> Void

  init(
    settings: AppSettings,
    actionHandler: @escaping ActionHandler,
    cancelHandler: @escaping @MainActor @Sendable () -> Void
  ) {
    self.actionHandler = actionHandler
    self.cancelHandler = cancelHandler
    rebuild(from: settings)
  }

  func update(settings: AppSettings) {
    rebuild(from: settings)
  }

  func reset(mode: MicAIMode) {
    guard var binding = bindings[mode] else {
      return
    }
    binding.machine = HotkeyStateMachine(
      activationMode: binding.machine.activationMode
    )
    binding.chordTracker = HotkeyChordTracker()
    bindings[mode] = binding
  }

  /// Only dictation honours the hold/toggle preference. The other three are
  /// always hold: a toggled command leaves the app recording with no visible
  /// owner if the user forgets the second press.
  private func rebuild(from settings: AppSettings) {
    var next: [MicAIMode: Binding] = [:]
    for mode in MicAIMode.allCases {
      guard let hotkey = settings.hotkey(for: mode) else {
        continue
      }
      let activation: DictationActivationMode =
        mode == .dictation ? settings.dictationActivationMode : .hold
      next[mode] = Binding(
        hotkey: hotkey,
        machine: HotkeyStateMachine(activationMode: activation)
      )
    }
    bindings = next
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
      for mode in MicAIMode.allCases {
        reset(mode: mode)
      }
      cancelHandler()
      return
    }

    // Fixed order so a settings state with two modes on one chord is at least
    // deterministic; `AppSettings.validated()` rejects that case up front.
    for mode in MicAIMode.allCases {
      guard var binding = bindings[mode] else {
        continue
      }
      // Both the chord tracker and the state machine are mutating structs, and
      // either can change state while producing no action (a press that only
      // arms the chord). The write-back therefore happens unconditionally --
      // guarding it on an action returned would drop half the presses.
      let matched = Self.matches(
        event,
        hotkey: binding.hotkey,
        chordTracker: &binding.chordTracker
      )
      var action: HotkeyAction?
      if matched, let input = inputEvent(from: event) {
        action = binding.machine.handle(input)
      }
      bindings[mode] = binding

      guard matched else {
        continue
      }
      if let action {
        actionHandler(mode, action)
      }
      return
    }
  }

  private static func matches(
    _ event: GlobalHotkeyEvent,
    hotkey: Hotkey,
    chordTracker: inout HotkeyChordTracker
  ) -> Bool {
    if hotkey == .rightOption {
      guard event.keyCode == hotkey.keyCode, event.kind == .flagsChanged else {
        return false
      }
      // Right Option pressed while ⌃, ⌘ or ⇧ is already down is the start of
      // a chord, not dictation. Releases always match so state stays balanced.
      return !event.optionDown || event.modifiers.isSubset(of: [.option])
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
