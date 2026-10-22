import Testing

@testable import MicAICore

struct HotkeyCaptureTests {
  @Test
  func chordWithModifiersIsAccepted() {
    let result = HotkeyCapture.resolve(keyCode: 2, modifiers: [.control, .option])
    #expect(result == .success(Hotkey(keyCode: 2, modifiers: [.control, .option])))
  }

  @Test
  func bareLetterIsRejected() {
    #expect(HotkeyCapture.resolve(keyCode: 2, modifiers: []) == .failure(.needsModifier))
  }

  @Test
  func escapeIsReservedEvenWithModifiers() {
    #expect(
      HotkeyCapture.resolve(keyCode: 53, modifiers: [.command]) == .failure(.reservedKey)
    )
  }

  @Test
  func rightOptionMapsToTheBuiltInDictationKey() {
    #expect(HotkeyCapture.resolve(keyCode: 61, modifiers: [.option]) == .success(.rightOption))
  }

  @Test
  func functionKeysWorkWithoutModifiers() {
    #expect(HotkeyCapture.resolve(keyCode: 96, modifiers: []) == .success(Hotkey(keyCode: 96)))
  }

  @Test
  func displayNameUsesKeyNamesAndModifierOrder() {
    #expect(Hotkey(keyCode: 2, modifiers: [.option, .control]).displayName == "⌃⌥D")
    #expect(Hotkey(keyCode: 96).displayName == "F5")
  }

  @Test
  func validationAppliesTheSameRulesAsTheRecorder() {
    var settings = AppSettings.defaults
    settings.commandHotkey = Hotkey(keyCode: 96)
    #expect((try? settings.validated()) != nil)

    settings.commandHotkey = Hotkey(keyCode: 2)
    #expect(throws: AppSettingsValidationError.unusableHotkey) {
      try settings.validated()
    }
  }
}
