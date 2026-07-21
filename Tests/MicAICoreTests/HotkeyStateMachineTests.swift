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
}
