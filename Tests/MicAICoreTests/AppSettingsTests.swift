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

@Suite
struct AppSettingsCompatibilityTests {
  @Test
  func settingsSavedBeforeTheseFeaturesExistedStillDecode() throws {
    // A build that predates refinement wrote only these four keys. Decoding
    // must fill in defaults rather than throw, which would silently reset the
    // user's hotkeys back to stock.
    let legacy = """
      {
        "dictationHotkey": { "keyCode": 61, "modifiers": [] },
        "dictationActivationMode": "hold",
        "llmModel": "gpt-5-codex"
      }
      """
    let data = try #require(legacy.data(using: .utf8))

    let settings = try JSONDecoder().decode(AppSettings.self, from: data)

    #expect(settings.dictationHotkey == .rightOption)
    #expect(settings.llmModel == "gpt-5-codex")
    #expect(settings.refinementEnabled)
    #expect(!settings.privacyMode)
    #expect(settings.historyEnabled)
    #expect(settings.defaultTone == .neutral)
    #expect(settings.styleOverrides.isEmpty)
  }

  @Test
  func newFieldsSurviveARoundTrip() throws {
    var settings = AppSettings.defaults
    settings.privacyMode = true
    settings.refinementEnabled = false
    settings.defaultTone = .professional
    settings.styleOverrides = ["com.example.app": .technical]
    settings.historyLimit = 50

    let decoded = try JSONDecoder().decode(
      AppSettings.self,
      from: try JSONEncoder().encode(settings)
    )

    #expect(decoded == settings)
  }

  @Test
  func refinementIsInactiveWithoutAModel() {
    var settings = AppSettings.defaults
    settings.refinementEnabled = true

    #expect(!settings.isRefinementActive)

    settings.llmModel = "gpt-5-codex"
    #expect(settings.isRefinementActive)
  }

  @Test
  func privacyModeSuppressesRefinementAndCommandsWithoutEditingThem() {
    var settings = AppSettings.defaults
    settings.llmModel = "gpt-5-codex"
    settings.commandHotkey = .controlOptionSpace
    settings.privacyMode = true

    #expect(!settings.isRefinementActive)
    #expect(!settings.areCommandsActive)
    // The user's own choices are untouched, so turning privacy mode off
    // restores them rather than requiring them to be set up again.
    #expect(settings.refinementEnabled)
    #expect(settings.commandHotkey == .controlOptionSpace)
  }

  @Test
  func commandHotkeyWithoutAModelIsAllowedInPrivacyMode() throws {
    // Outside privacy mode this combination is a validation error, because a
    // command with no model does nothing. In privacy mode commands are off
    // anyway, so the missing model is not a problem to report.
    var settings = AppSettings.defaults
    settings.commandHotkey = .controlOptionSpace
    settings.privacyMode = true

    #expect(throws: Never.self) { try settings.validated() }
  }

  @Test
  func historyLimitIsClampedToASaneRange() throws {
    var settings = AppSettings.defaults
    settings.historyLimit = 0
    #expect(try settings.validated().historyLimit == 1)

    settings.historyLimit = 99_999
    #expect(try settings.validated().historyLimit == 2_000)
  }
}
