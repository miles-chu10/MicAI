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

  @Test(arguments: [
    "gpt-transcribe", " gpt-live-transcribe ", "gpt-4o-transcribe",
    "gpt-4o-mini-transcribe-2025-12-15", "gpt-4o-transcribe-diarize", "whisper-1",
  ])
  func audioOnlyOverridesMigrateWithoutResettingOtherSettings(_ model: String) throws {
    var original = AppSettings.defaults
    original.llmModel = model
    original.dictationHotkey = .controlOptionSpace
    original.dictationActivationMode = .toggle
    original.commandHotkey = .commandShiftSpace
    original.translateHotkey = .controlOptionT
    original.askHotkey = .controlOptionA
    original.translationTargetLanguage = "Spanish"
    original.historyEnabled = false
    original.historyLimit = 37
    original.defaultTone = .professional
    original.styleOverrides = ["synthetic.app": .technical]
    original.dictationProvider = .openAI
    original.openAITranscriptionModel = "gpt-transcribe"
    original.openAITranscriptionFallbackEnabled = false
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))
    original.llmModel = ""
    #expect(try decoded.validated() == original)
    let persisted = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(decoded))
    #expect(persisted == original)
  }

  @Test
  func freshAudioOnlyTextOverrideIsRejectedWithoutChangingTheDraft() {
    var settings = AppSettings.defaults
    settings.llmModel = " gpt-transcribe "
    #expect(throws: AppSettingsValidationError.transcriptionOnlyTextModel) {
      try settings.validated()
    }
    #expect(settings.llmModel == " gpt-transcribe ")
  }

  @Test
  func arbitraryUnknownModelIsPreservedForCodexValidation() throws {
    var settings = AppSettings.defaults
    settings.llmModel = "custom-text-model"
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(try decoded.validated().llmModel == "custom-text-model")
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
  func validationAllowsSubscriptionDefaultWhenCommandsAreEnabled() throws {
    let settings = AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: .controlOptionSpace,
      dictationActivationMode: .hold,
      llmModel: " \n "
    )

    #expect(try settings.validated().llmModel == "")
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
          "refinementEnabled",
          "cloudCleanupConsented",
          "privacyMode",
          "historyEnabled",
          "historyLimit",
          "defaultTone",
          "styleOverrides",
          "translationTargetLanguage",
          "askAlwaysOpensWindow",
          "dictationProvider",
          "openAITranscriptionModel",
          "openAITranscriptionFallbackEnabled",
          "speechModel",
          "customInstructions",
          "soundFeedback",
          "cleanupEngine",
          "livePreview",
          "customModes",
        ]
    )
    let serializedKeys = object.keys.map { $0.lowercased() }
    #expect(!serializedKeys.contains { $0.contains("apikey") })
    #expect(!serializedKeys.contains { $0.contains("credential") })
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
    // Clean-up was never chosen, so it stays off and dictation stays local.
    #expect(!settings.refinementEnabled)
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
  func refinementRunsWithTheSubscriptionDefaultModelOnceConsented() {
    var settings = AppSettings.defaults
    settings.refinementEnabled = true
    #expect(!settings.isRefinementActive)

    settings.cloudCleanupConsented = true
    #expect(settings.isRefinementActive)

    settings.privacyMode = true
    #expect(!settings.isRefinementActive)
  }

  @Test
  func privacyModeSuppressesRefinementAndCommandsWithoutEditingThem() {
    var settings = AppSettings.defaults
    settings.llmModel = "gpt-5-codex"
    settings.commandHotkey = .controlOptionSpace
    settings.refinementEnabled = true
    settings.cloudCleanupConsented = true
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
  func leavingPrivacyModeWithoutAModelSucceedsWithTheModesOff() throws {
    // Saved while private with no model or language, then switched back from
    // the menu: the switch must not fail validation.
    var settings = AppSettings.defaults
    settings.llmModel = ""
    settings.commandHotkey = .controlOptionSpace
    settings.translateHotkey = .controlOptionT
    settings.askHotkey = .controlOptionA
    settings.privacyMode = false

    #expect(throws: AppSettingsValidationError.self) { try settings.validated() }
    let saved = try settings.validated(waivingModelRequirements: true)

    // A blank model is the Codex default, so only the mode missing its
    // language stays off.
    #expect(!saved.privacyMode)
    #expect(saved.commandHotkey == .controlOptionSpace)
    #expect(saved.areCommandsActive)
    #expect(!saved.isTranslateActive)
    #expect(saved.isAskActive)
  }

  @Test
  func waivingStillReportsStructuralProblems() {
    var settings = AppSettings.defaults
    settings.commandHotkey = settings.dictationHotkey

    #expect(throws: AppSettingsValidationError.duplicateHotkeys) {
      try settings.validated(waivingModelRequirements: true)
    }
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
  func askWithoutAModelUsesTheSubscriptionDefault() throws {
    var settings = AppSettings.defaults
    settings.askHotkey = .controlOptionA

    #expect(try settings.validated().llmModel == "")
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
    #expect(MicAIMode.custom.capturesSelection)
    #expect(MicAIMode.builtIn.count == 4)
    #expect(MicAIMode.allCases.count == 5)
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

    #expect(settings.speechModel == .english)
    #expect(settings.customInstructions.isEmpty)
    #expect(settings.soundFeedback)
    #expect(settings.cleanupEngine == .languageModel)
    #expect(settings.livePreview)
    #expect(settings.customModes.isEmpty)
  }

  @Test
  func onDeviceCleanUpRunsInPrivacyModeAndWithoutAModel() {
    var settings = AppSettings.defaults
    settings.refinementEnabled = true
    settings.cleanupEngine = .onDevice
    settings.privacyMode = true
    #expect(settings.llmModel.isEmpty)
    #expect(settings.refinementRoute == .onDevice)

    settings.refinementEnabled = false
    #expect(settings.refinementRoute == nil)
  }

  @Test
  func languageModelCleanUpUsesTheCodexDefaultButNotInPrivacyMode() {
    var settings = AppSettings.defaults
    settings.refinementEnabled = true
    settings.cloudCleanupConsented = true
    settings.cleanupEngine = .languageModel
    #expect(settings.llmModel.isEmpty)
    #expect(settings.refinementRoute == .languageModel)

    settings.privacyMode = true
    #expect(settings.refinementRoute == nil)
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

@Suite
struct CloudCleanupConsentTests {
  @Test
  func newInstallsKeepDictationOnThisMac() {
    let settings = AppSettings.defaults
    #expect(!settings.refinementEnabled)
    #expect(!settings.cloudCleanupConsented)
    #expect(settings.refinementRoute == nil)
  }

  @Test
  func olderSettingsKeepTheirChoiceButPauseCloudCleanUpUntilConfirmed() throws {
    let legacy = """
      {
        "dictationHotkey": { "keyCode": 61, "modifiers": [] },
        "dictationActivationMode": "hold",
        "llmModel": "",
        "refinementEnabled": true
      }
      """
    var settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))

    #expect(settings.refinementEnabled)
    #expect(!settings.cloudCleanupConsented)
    #expect(settings.refinementRoute == nil)

    settings.cloudCleanupConsented = true
    #expect(settings.refinementRoute == .languageModel)
  }

  @Test
  func onDeviceCleanUpNeedsNoCloudConsent() {
    var settings = AppSettings.defaults
    settings.refinementEnabled = true
    settings.cleanupEngine = .onDevice
    #expect(settings.refinementRoute == .onDevice)
  }

  @Test
  func consentSurvivesARoundTrip() throws {
    var settings = AppSettings.defaults
    settings.refinementEnabled = true
    settings.cloudCleanupConsented = true
    let decoded = try JSONDecoder().decode(
      AppSettings.self,
      from: JSONEncoder().encode(settings)
    )
    #expect(decoded.cloudCleanupConsented)
    #expect(decoded.refinementRoute == .languageModel)
  }
}
