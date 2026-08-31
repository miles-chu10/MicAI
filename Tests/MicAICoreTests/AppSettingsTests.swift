import Foundation
import MicAICore
import Testing

@Suite
struct AppSettingsTests {
  @Test
  func defaultsUseRightOptionHoldAndNoCommandHotkey() {
    let settings = AppSettings.defaults

    #expect(settings.dictationHotkey == .rightOption)
    #expect(settings.dictationActivationMode == .hold)
    #expect(settings.commandHotkey == nil)
    #expect(settings.llmModel == "")
    #expect(settings.dictationProvider == .parakeet)
    #expect(settings.openAITranscriptionModel == "gpt-transcribe")
    #expect(settings.openAITranscriptionFallbackEnabled)
  }

  @Test
  func validationTrimsModel() throws {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: Hotkey(keyCode: 49, modifiers: [.command, .shift]),
      dictationActivationMode: .toggle,
      llmModel: "  gpt-test  "
    )

    #expect(try settings.validated().llmModel == "gpt-test")
  }

  @Test
  func validationAllowsEmptyModelWhileCommandsAreDisabled() throws {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: nil,
      dictationActivationMode: .hold,
      llmModel: " \n "
    )

    #expect(try settings.validated().llmModel == "")
  }

  @Test
  func validationRejectsEmptyModelWhenCommandsAreEnabled() {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: .controlOptionSpace,
      dictationActivationMode: .hold,
      llmModel: " \n "
    )

    do {
      _ = try settings.validated()
      Issue.record("Expected validation to reject an empty model")
    } catch {
      #expect(error as? AppSettingsValidationError == .emptyModel)
    }
  }

  @Test
  func openAITranscriptionModelTrimsAndAllowsCustomIDs() throws {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: nil,
      dictationActivationMode: .hold,
      llmModel: "",
      dictationProvider: .openAI,
      openAITranscriptionModel: "  custom-transcriber-v2  ",
      openAITranscriptionFallbackEnabled: false
    )

    let validated = try settings.validated()
    #expect(validated.openAITranscriptionModel == "custom-transcriber-v2")
    #expect(validated.dictationTranscriptionRequest.model == "custom-transcriber-v2")
    #expect(!validated.dictationTranscriptionRequest.fallbackToParakeet)
  }

  @Test
  func validationRejectsEmptyOpenAITranscriptionModel() {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: nil,
      dictationActivationMode: .hold,
      llmModel: "",
      dictationProvider: .openAI,
      openAITranscriptionModel: " \n "
    )

    #expect(throws: AppSettingsValidationError.emptyOpenAITranscriptionModel) {
      try settings.validated()
    }
  }

  @Test
  func legacySettingsDecodeToParakeetWithoutResettingExistingValues() throws {
    let legacy = """
      {
        "dictationHotkey": {"keyCode": 49, "modifiers": ["control", "option"]},
        "commandHotkey": null,
        "dictationActivationMode": "toggle",
        "llmModel": "legacy-command-model"
      }
      """

    let decoded = try JSONDecoder().decode(
      AppSettings.self,
      from: Data(legacy.utf8)
    )

    #expect(decoded.dictationHotkey == .controlOptionSpace)
    #expect(decoded.dictationActivationMode == .toggle)
    #expect(decoded.llmModel == "legacy-command-model")
    #expect(decoded.dictationProvider == .parakeet)
    #expect(decoded.openAITranscriptionModel == "gpt-transcribe")
    #expect(decoded.openAITranscriptionFallbackEnabled)
  }

  @Test
  func validationRejectsDuplicateHotkeys() {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: .rightOption,
      dictationActivationMode: .hold,
      llmModel: "gpt-test"
    )

    do {
      _ = try settings.validated()
      Issue.record("Expected validation to reject duplicate hotkeys")
    } catch {
      #expect(error as? AppSettingsValidationError == .duplicateHotkeys)
    }
  }

  @Test
  func validationRejectsUnmodifiedNonModifierKey() {
    let settings = AppSettings(
      dictationHotkey: Hotkey(keyCode: 49),
      commandHotkey: nil,
      dictationActivationMode: .hold,
      llmModel: ""
    )

    do {
      _ = try settings.validated()
      Issue.record("Expected validation to reject an unusable hotkey")
    } catch {
      #expect(error as? AppSettingsValidationError == .unusableHotkey)
    }
  }

  @Test
  func hotkeyNamesAreHumanReadable() {
    #expect(Hotkey.rightOption.displayName == "Right Option")
    #expect(Hotkey.controlOptionSpace.displayName == "⌃⌥Space")
    #expect(Hotkey.commandShiftSpace.displayName == "⇧⌘Space")
  }

  @Test
  func serializationRoundTripsOnlyNonSecretSettings() throws {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: Hotkey(keyCode: 49, modifiers: [.command]),
      dictationActivationMode: .toggle,
      llmModel: "gpt-test",
      dictationProvider: .openAI,
      openAITranscriptionModel: "custom-transcriber",
      openAITranscriptionFallbackEnabled: false
    )

    let data = try JSONEncoder().encode(settings)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(
      Set(object.keys)
        == [
          "dictationHotkey",
          "commandHotkey",
          "dictationActivationMode",
          "llmModel",
          "dictationProvider",
          "openAITranscriptionModel",
          "openAITranscriptionFallbackEnabled",
        ]
    )
    let serializedKeys = object.keys.map { $0.lowercased() }
    #expect(!serializedKeys.contains { $0.contains("apikey") })
    #expect(!serializedKeys.contains { $0.contains("credential") })
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
  }
}
