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

@Suite
struct HybridActivationTests {
  @Test
  func longPressBehavesLikeHold() {
    var machine = HotkeyStateMachine(activationMode: .hybrid)

    #expect(machine.handle(.pressed(isRepeat: false), at: 10) == .startRecording)
    #expect(machine.handle(.released, at: 11.2) == .stopRecording)
    #expect(!machine.isRecording)
    #expect(!machine.isLocked)
  }

  @Test
  func quickTapLocksUntilTheNextPress() {
    var machine = HotkeyStateMachine(activationMode: .hybrid)

    #expect(machine.handle(.pressed(isRepeat: false), at: 10) == .startRecording)
    #expect(machine.handle(.released, at: 10.1) == .lockRecording)
    #expect(machine.isRecording)
    #expect(machine.isLocked)

    // Releasing after the stopping press must not start anything new.
    #expect(machine.handle(.pressed(isRepeat: false), at: 14) == .stopRecording)
    #expect(machine.handle(.released, at: 14.05) == nil)
    #expect(!machine.isRecording)
    #expect(!machine.isLocked)
  }

  @Test
  func releaseExactlyAtTheThresholdCountsAsAHold() {
    var machine = HotkeyStateMachine(activationMode: .hybrid)

    _ = machine.handle(.pressed(isRepeat: false), at: 0)
    #expect(
      machine.handle(.released, at: HotkeyStateMachine.tapThreshold) == .stopRecording
    )
  }

  @Test
  func repeatsWhileHeldAreIgnored() {
    var machine = HotkeyStateMachine(activationMode: .hybrid)

    _ = machine.handle(.pressed(isRepeat: false), at: 0)
    #expect(machine.handle(.pressed(isRepeat: true), at: 0.5) == nil)
    #expect(machine.handle(.released, at: 1) == .stopRecording)
  }

  @Test
  func cancelClearsTheLock() {
    var machine = HotkeyStateMachine(activationMode: .hybrid)
    _ = machine.handle(.pressed(isRepeat: false), at: 0)
    _ = machine.handle(.released, at: 0.1)

    #expect(machine.handle(.cancel) == .cancelRecording)
    #expect(!machine.isLocked)
    // A fresh press after cancelling starts a new recording, not a stop.
    #expect(machine.handle(.pressed(isRepeat: false), at: 5) == .startRecording)
  }
}
