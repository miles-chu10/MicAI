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
          "refinementEnabled",
          "privacyMode",
          "historyEnabled",
          "historyLimit",
          "defaultTone",
          "styleOverrides",
          "translationTargetLanguage",
          "askAlwaysOpensWindow",
          "llmProvider",
          "speechModel",
          "customInstructions",
          "soundFeedback",
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

@Suite
struct TranslateAndAskSettingsTests {
  @Test
  func everyConfiguredHotkeyMustBeDistinct() {
    // Two modes on one chord means whichever the monitor tests first silently
    // wins, so this is rejected rather than resolved by ordering.
    var settings = base()
    settings.translateHotkey = .controlOptionT
    settings.askHotkey = .controlOptionT

    #expect(throws: AppSettingsValidationError.duplicateHotkeys) {
      try settings.validated()
    }
  }

  @Test
  func translateCollidingWithDictationIsRejected() {
    var settings = base()
    settings.translateHotkey = .rightOption

    #expect(throws: AppSettingsValidationError.duplicateHotkeys) {
      try settings.validated()
    }
  }

  @Test
  func distinctHotkeysAcrossAllFourModesValidate() throws {
    var settings = base()
    settings.commandHotkey = .controlOptionSpace
    settings.translateHotkey = .controlOptionT
    settings.askHotkey = .controlOptionA
    settings.translationTargetLanguage = "Spanish"

    #expect(throws: Never.self) { try settings.validated() }
  }

  @Test
  func translateWithoutALanguageIsRejected() {
    var settings = base()
    settings.translateHotkey = .controlOptionT

    #expect(throws: AppSettingsValidationError.emptyTargetLanguage) {
      try settings.validated()
    }
  }

  @Test
  func targetLanguageIsTrimmed() throws {
    var settings = base()
    settings.translateHotkey = .controlOptionT
    settings.translationTargetLanguage = "  Japanese  "

    #expect(try settings.validated().translationTargetLanguage == "Japanese")
  }

  @Test
  func askOrTranslateWithoutAModelIsRejected() {
    var settings = AppSettings.defaults
    settings.askHotkey = .controlOptionA

    #expect(throws: AppSettingsValidationError.emptyModel) {
      try settings.validated()
    }
  }

  @Test
  func privacyModeSuppressesBothWithoutEditingThem() {
    var settings = base()
    settings.translateHotkey = .controlOptionT
    settings.translationTargetLanguage = "Spanish"
    settings.askHotkey = .controlOptionA
    settings.privacyMode = true

    #expect(!settings.isTranslateActive)
    #expect(!settings.isAskActive)
    #expect(settings.translateHotkey == .controlOptionT)
    #expect(settings.askHotkey == .controlOptionA)
  }

  @Test
  func privacyModeAlsoWaivesTheLanguageAndModelRequirements() {
    // With the features suppressed there is nothing for those values to feed,
    // so demanding them would be a validation error the user cannot act on.
    var settings = AppSettings.defaults
    settings.translateHotkey = .controlOptionT
    settings.askHotkey = .controlOptionA
    settings.privacyMode = true

    #expect(throws: Never.self) { try settings.validated() }
  }

  @Test
  func translateNeedsBothAModelAndALanguageToBeActive() {
    var settings = base()
    settings.translateHotkey = .controlOptionT
    #expect(!settings.isTranslateActive)

    settings.translationTargetLanguage = "Spanish"
    #expect(settings.isTranslateActive)
  }

  @Test
  func hotkeyLookupCoversEveryMode() {
    var settings = base()
    settings.commandHotkey = .controlOptionSpace
    settings.translateHotkey = .controlOptionT
    settings.askHotkey = .controlOptionA

    #expect(settings.hotkey(for: .dictation) == .rightOption)
    #expect(settings.hotkey(for: .command) == .controlOptionSpace)
    #expect(settings.hotkey(for: .translate) == .controlOptionT)
    #expect(settings.hotkey(for: .ask) == .controlOptionA)
  }

  @Test
  func newHotkeysRenderWithTheirKeyLetter() {
    #expect(Hotkey.controlOptionT.displayName == "⌃⌥T")
    #expect(Hotkey.controlOptionA.displayName == "⌃⌥A")
  }

  @Test
  func settingsSavedBeforeTranslateAndAskExistedStillDecode() throws {
    let legacy = """
      {
        "dictationHotkey": { "keyCode": 61, "modifiers": [] },
        "dictationActivationMode": "hold",
        "llmModel": "gpt-5-codex",
        "refinementEnabled": true
      }
      """
    let data = try #require(legacy.data(using: .utf8))

    let settings = try JSONDecoder().decode(AppSettings.self, from: data)

    #expect(settings.translateHotkey == nil)
    #expect(settings.askHotkey == nil)
    #expect(settings.translationTargetLanguage.isEmpty)
    #expect(!settings.askAlwaysOpensWindow)
  }

  @Test
  func modeMetadataMatchesBehaviour() {
    #expect(!MicAIMode.dictation.capturesSelection)
    #expect(MicAIMode.command.capturesSelection)
    #expect(MicAIMode.translate.capturesSelection)
    #expect(MicAIMode.ask.capturesSelection)
    #expect(MicAIMode.allCases.count == 4)
  }

  private func base() -> AppSettings {
    var settings = AppSettings.defaults
    settings.llmModel = "gpt-5-codex"
    return settings
  }
}

@Suite
struct FeatureSettingsCompatibilityTests {
  @Test
  func settingsSavedBeforeProviderAndSpeechModelExistedGetSafeDefaults() throws {
    let legacy = """
      {
        "dictationHotkey": { "keyCode": 61, "modifiers": [] },
        "dictationActivationMode": "hold",
        "llmModel": "gpt-test"
      }
      """
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))

    #expect(settings.llmProvider == .chatGPTSubscription)
    #expect(settings.speechModel == .english)
    #expect(settings.customInstructions.isEmpty)
    #expect(settings.soundFeedback)
  }

  @Test
  func hybridActivationRoundTrips() throws {
    var settings = AppSettings.defaults
    settings.dictationActivationMode = .hybrid
    let data = try JSONEncoder().encode(settings)
    #expect(
      try JSONDecoder().decode(AppSettings.self, from: data).dictationActivationMode == .hybrid
    )
  }

  @Test
  func validationTrimsCustomInstructions() throws {
    var settings = AppSettings.defaults
    settings.customInstructions = "  Use British spelling.\n"
    #expect(try settings.validated().customInstructions == "Use British spelling.")
  }

  @Test
  func keyCapsListOneLabelPerKey() {
    #expect(Hotkey.rightOption.keyCaps == ["Right ⌥"])
    #expect(Hotkey.controlOptionSpace.keyCaps == ["⌃", "⌥", "Space"])
    #expect(Hotkey.commandShiftSpace.keyCaps == ["⇧", "⌘", "Space"])
  }
}
