import Foundation
import MicAICore
import Testing

@Suite
struct CustomModeEngineTests {
  private let bullets = CustomMode(
    name: "Bullet points",
    instructions: "Make a bulleted list.",
    output: .insert
  )

  @Test
  func sendsTheModeInstructionsAndWhatWasSaid() async throws {
    let transformer = CapturingTransformer(output: "- one\n- two")
    let engine = CustomModeEngine(transformer: transformer)

    let result = try await engine.run(
      bullets,
      spokenText: " one and two ",
      selectedText: nil,
      model: "gpt-test"
    )

    let request = try #require(await transformer.lastRequest)
    #expect(request.kind == .custom)
    #expect(request.selectedText == nil)
    #expect(
      request.instruction == "Mode instructions: Make a bulleted list.\n\nWhat I said: one and two"
    )
    #expect(result.text == "- one\n- two")
    #expect(result.insertionIntent == .insert("- one\n- two"))
  }

  @Test
  func aSelectionIsReplacedAndSentAsData() async throws {
    let transformer = CapturingTransformer(output: "- a\n- b")
    let engine = CustomModeEngine(transformer: transformer)

    let result = try await engine.run(
      bullets,
      spokenText: "",
      selectedText: "a, b",
      model: "gpt-test"
    )

    #expect(await transformer.lastRequest?.selectedText == "a, b")
    #expect(await transformer.lastRequest?.instruction.hasSuffix("What I said: (nothing)") == true)
    #expect(result.insertionIntent == .replaceSelection("- a\n- b"))
  }

  @Test
  func windowModesReportTheirOutput() async throws {
    var mode = bullets
    mode.output = .window
    let result = try await CustomModeEngine(transformer: CapturingTransformer(output: "x"))
      .run(mode, spokenText: "hi", selectedText: nil, model: "gpt-test")
    #expect(result.output == .window)
  }

  @Test
  func nothingSaidAndNothingSelectedIsAnError() async {
    let engine = CustomModeEngine(transformer: CapturingTransformer(output: "x"))
    do {
      _ = try await engine.run(bullets, spokenText: "  ", selectedText: nil, model: "gpt-test")
      Issue.record("Expected asrFailed")
    } catch {
      #expect(error as? MicAIError == .asrFailed)
    }
  }

  @Test
  func emptyModelOutputIsAnError() async {
    let engine = CustomModeEngine(transformer: CapturingTransformer(output: "  \n"))
    do {
      _ = try await engine.run(bullets, spokenText: "hi", selectedText: nil, model: "gpt-test")
      Issue.record("Expected llmIncomplete")
    } catch {
      #expect(error as? MicAIError == .llmIncomplete)
    }
  }
}

@Suite
struct CustomModeSettingsTests {
  @Test
  func customModeShortcutsMustNotCollideWithOtherModes() {
    var settings = AppSettings.defaults
    settings.llmModel = "gpt-test"
    settings.askHotkey = .controlOptionA
    settings.customModes = [
      CustomMode(name: "Mine", instructions: "Do it.", hotkey: .controlOptionA)
    ]

    #expect(throws: AppSettingsValidationError.duplicateHotkeys) {
      try settings.validated()
    }
  }

  @Test
  func incompleteModesAreRejected() {
    var settings = AppSettings.defaults
    settings.customModes = [CustomMode(name: "  ", instructions: "Do it.")]

    #expect(throws: AppSettingsValidationError.incompleteCustomMode) {
      try settings.validated()
    }
  }

  @Test
  func aCustomModeWithAShortcutNeedsAModel() {
    var settings = AppSettings.defaults
    settings.customModes = [
      CustomMode(name: "Mine", instructions: "Do it.", hotkey: .controlOptionSpace)
    ]

    #expect(throws: AppSettingsValidationError.emptyModel) {
      try settings.validated()
    }
  }

  @Test
  func customModesRoundTrip() throws {
    var settings = AppSettings.defaults
    settings.customModes = CustomMode.templates
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(decoded.customModes == CustomMode.templates)
  }

  @Test
  func templatesAreComplete() {
    let incomplete = CustomMode.templates.filter { !$0.isComplete }
    #expect(incomplete.isEmpty)
  }

  @Test
  func privacyModePausesCustomModes() {
    var settings = AppSettings.defaults
    settings.llmModel = "gpt-test"
    #expect(settings.areCustomModesActive)
    settings.privacyMode = true
    #expect(!settings.areCustomModesActive)
  }
}

@Suite
struct HotkeyRecordingTests {
  @Test
  func needsControlOptionOrCommand() {
    #expect(Hotkey.recordable(keyCode: 0, modifiers: [.shift]) == nil)
    #expect(Hotkey.recordable(keyCode: 0, modifiers: []) == nil)
    #expect(Hotkey.recordable(keyCode: 0, modifiers: [.command, .shift]) != nil)
  }

  @Test
  func escapeAndDeleteCannotBeShortcuts() {
    #expect(Hotkey.recordable(keyCode: 53, modifiers: [.control]) == nil)
    #expect(Hotkey.recordable(keyCode: 51, modifiers: [.option]) == nil)
  }

  @Test
  func recordedKeysHaveReadableNames() {
    let hotkey = Hotkey(keyCode: 11, modifiers: [.control, .option])
    #expect(hotkey.displayName == "⌃⌥B")
    #expect(Hotkey(keyCode: 122, modifiers: [.command]).keyCaps == ["⌘", "F1"])
  }
}

@Suite
struct HistoryModeNameTests {
  @Test
  func entriesWrittenBeforeCustomModesStillDecode() throws {
    let legacy = """
      [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":0,"mode":"dictation",
        "rawTranscript":"hi","finalText":"Hi.","audioDuration":1,"refined":true}]
      """
    let entries = try JSONDecoder().decode([HistoryEntry].self, from: Data(legacy.utf8))
    #expect(entries.first?.modeName == nil)
  }
}

private actor CapturingTransformer: LLMTransforming {
  private let output: String
  private(set) var lastRequest: LLMRequest?

  init(output: String) {
    self.output = output
  }

  func transform(_ request: LLMRequest) async throws -> String {
    lastRequest = request
    return output
  }
}
