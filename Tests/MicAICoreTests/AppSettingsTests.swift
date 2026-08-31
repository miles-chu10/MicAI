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
    #expect(settings.llmProvider == .openAIAPIKey)
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
      llmProvider: .chatGPTSubscription,
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
          "llmProvider",
          "llmModel",
        ]
    )
    #expect(object["llmProvider"] as? String == "chatGPTSubscription")
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
  }

  @Test
  func decodingSettingsWithoutProviderDefaultsToOpenAIAPIKey() throws {
    let legacy = """
      {
        "dictationHotkey": {"keyCode": 61, "modifiers": []},
        "commandHotkey": null,
        "dictationActivationMode": "hold",
        "llmModel": "gpt-test"
      }
      """

    let settings = try JSONDecoder().decode(
      AppSettings.self,
      from: Data(legacy.utf8)
    )

    #expect(settings.llmProvider == .openAIAPIKey)
    #expect(settings.llmModel == "gpt-test")
  }

  @Test
  func providerSummariesMatchTheSelectedProvider() {
    #expect(
      ProviderStatus.readyToAttempt.summary(for: .openAIAPIKey)
        == "The OPENAI_API_KEY environment variable will be checked when a command runs."
    )
    #expect(
      ProviderStatus.readyToAttempt.summary(for: .chatGPTSubscription)
        == "Codex credential will be checked when a command runs."
    )
    #expect(
      ProviderStatus.retryingCredential.summary(for: .openAIAPIKey)
        == "Rechecking authorization with the OpenAI API."
    )
    #expect(
      ProviderStatus.retryingCredential.summary(for: .chatGPTSubscription)
        == "Reloading the Codex credential after authorization failed."
    )
  }
}
