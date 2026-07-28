import MicAICore
import Testing

@Suite
struct HotkeyStateMachineTests {
  @Test
  func holdStartsOnPressAndStopsOnRelease() {
    var machine = HotkeyStateMachine(activationMode: .hold)

    #expect(machine.handle(.pressed(isRepeat: false)) == .startRecording)
    #expect(machine.handle(.released) == .stopRecording)
    #expect(!machine.isRecording)
  }

  @Test
  func holdIgnoresRepeatAndDuplicatePress() {
    var machine = HotkeyStateMachine(activationMode: .hold)

    #expect(machine.handle(.pressed(isRepeat: true)) == nil)
    #expect(machine.handle(.pressed(isRepeat: false)) == .startRecording)
    #expect(machine.handle(.pressed(isRepeat: false)) == nil)
  }

  @Test
  func toggleStartsAndStopsOnDistinctPresses() {
    var machine = HotkeyStateMachine(activationMode: .toggle)

    #expect(machine.handle(.pressed(isRepeat: false)) == .startRecording)
    #expect(machine.handle(.released) == nil)
    #expect(machine.handle(.pressed(isRepeat: false)) == .stopRecording)
  }

  @Test
  func cancelStopsActiveRecording() {
    var machine = HotkeyStateMachine(activationMode: .toggle)
    _ = machine.handle(.pressed(isRepeat: false))

    #expect(machine.handle(.cancel) == .cancelRecording)
    #expect(machine.handle(.cancel) == nil)
    #expect(!machine.isRecording)
  }

  @Test
  func chordTrackerAcceptsPrimaryKeyFirstRelease() {
    var tracker = HotkeyChordTracker()
    var machine = HotkeyStateMachine(activationMode: .hold)
    let hotkey = Hotkey.controlOptionSpace

    let matchedPress = tracker.matches(
      .keyDown(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers),
      hotkey: hotkey
    )
    #expect(matchedPress)
    #expect(machine.handle(.pressed(isRepeat: false)) == .startRecording)
    let matchedRelease = tracker.matches(
      .keyUp(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers),
      hotkey: hotkey
    )
    #expect(matchedRelease)
    #expect(machine.handle(.released) == .stopRecording)
  }

  @Test
  func chordTrackerAcceptsModifierFirstReleaseAndIgnoresUnrelatedKeyUp() {
    var tracker = HotkeyChordTracker()
    var machine = HotkeyStateMachine(activationMode: .hold)
    let hotkey = Hotkey.controlOptionSpace

    let matchedPress = tracker.matches(
      .keyDown(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers),
      hotkey: hotkey
    )
    #expect(matchedPress)
    #expect(machine.handle(.pressed(isRepeat: false)) == .startRecording)
    let matchedUnrelatedRelease = tracker.matches(
      .keyUp(keyCode: 48, modifiers: []),
      hotkey: hotkey
    )
    #expect(!matchedUnrelatedRelease)
    #expect(machine.isRecording)
    let matchedRelease = tracker.matches(
      .keyUp(keyCode: hotkey.keyCode, modifiers: []),
      hotkey: hotkey
    )
    #expect(matchedRelease)
    #expect(machine.handle(.released) == .stopRecording)
    let matchedDuplicateRelease = tracker.matches(
      .keyUp(keyCode: hotkey.keyCode, modifiers: []),
      hotkey: hotkey
    )
    #expect(!matchedDuplicateRelease)
  }
}
