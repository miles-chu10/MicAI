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
    #expect(settings.llmProvider == .chatgptSubscription)
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
      llmProvider: .openAIAPIKey
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
          "llmProvider",
        ]
    )
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
  }

  @Test
  func decodingLegacyJSONDefaultsToChatGPTSubscription() throws {
    let json = """
      {
        "dictationHotkey": {
          "keyCode": 61,
          "modifiers": []
        },
        "commandHotkey": null,
        "dictationActivationMode": "hold",
        "llmModel": ""
      }
      """

    let settings = try JSONDecoder().decode(
      AppSettings.self,
      from: Data(json.utf8)
    )

    #expect(settings.llmProvider == .chatgptSubscription)
  }
}
