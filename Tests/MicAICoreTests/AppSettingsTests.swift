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
  func validationRejectsEmptyModel() {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: nil,
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
  func serializationRoundTripsOnlyNonSecretSettings() throws {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: Hotkey(keyCode: 49, modifiers: [.command]),
      dictationActivationMode: .toggle,
      llmModel: "gpt-test"
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
        ]
    )
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
  }
}
