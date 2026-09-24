import Foundation

public enum DictationActivationMode: String, Codable, CaseIterable, Sendable {
  case hold
  case toggle

  public var displayName: String {
    switch self {
    case .hold:
      "Hold"
    case .toggle:
      "Toggle"
    }
  }
}

public enum HotkeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
  case command
  case control
  case option
  case shift
}

public struct Hotkey: Codable, Hashable, Sendable {
  public static let rightOption = Hotkey(keyCode: 61)
  public static let controlOptionSpace = Hotkey(
    keyCode: 49,
    modifiers: [.control, .option]
  )
  public static let commandShiftSpace = Hotkey(
    keyCode: 49,
    modifiers: [.command, .shift]
  )
  public static let controlOptionT = Hotkey(
    keyCode: 17,
    modifiers: [.control, .option]
  )
  public static let controlOptionA = Hotkey(
    keyCode: 0,
    modifiers: [.control, .option]
  )

  /// Virtual key codes to labels, for the ones offered in Settings. Values are
  /// Carbon `kVK_ANSI_*` constants; anything unlisted falls back to its number
  /// rather than guessing at a character that depends on keyboard layout.
  static let keyNames: [UInt16: String] = [
    0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
    38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
    15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
    28: "8", 25: "9",
    49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
    27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".",
    44: "/", 42: "\\", 50: "`",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
    100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    123: "←", 124: "→", 125: "↓", 126: "↑",
  ]

  public var keyCode: UInt16
  public var modifiers: Set<HotkeyModifier>

  public init(keyCode: UInt16, modifiers: Set<HotkeyModifier> = []) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public var displayName: String {
    if self == .rightOption {
      return "Right Option"
    }

    let modifierNames = HotkeyModifier.displayOrder.compactMap { modifier in
      modifiers.contains(modifier) ? modifier.symbol : nil
    }
    let keyName = Self.keyNames[keyCode] ?? "Key \(keyCode)"
    return modifierNames.joined() + keyName
  }
}

public enum AppSettingsValidationError: Error, Equatable, Sendable {
  case emptyOpenAITranscriptionModel
  case duplicateHotkeys
  case unusableHotkey
  case emptyTargetLanguage
}

extension AppSettingsValidationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyOpenAITranscriptionModel:
      "Enter an OpenAI transcription model."
    case .duplicateHotkeys:
      "Each mode needs its own hotkey."
    case .unusableHotkey:
      "Choose a supported hotkey with modifiers."
    case .emptyTargetLanguage:
      "Enter a language to translate into."
    }
  }
}

public struct AppSettings: Codable, Equatable, Sendable {
  public static let defaults = AppSettings(
    dictationHotkey: .rightOption,
    commandHotkey: nil,
    dictationActivationMode: .hold,
    llmModel: "",
    dictationProvider: .parakeet,
    openAITranscriptionModel: SpeechTranscriptionRequest.defaultOpenAIModel,
    openAITranscriptionFallbackEnabled: true
  )

  public var dictationHotkey: Hotkey
  public var commandHotkey: Hotkey?
  public var dictationActivationMode: DictationActivationMode
  public var llmModel: String
  public var dictationProvider: DictationProvider
  public var openAITranscriptionModel: String
  public var openAITranscriptionFallbackEnabled: Bool

  /// Send dictated transcripts through the LLM for clean-up and tone matching.
  /// Off means Parakeet's output goes to the cursor as-is.
  public var refinementEnabled: Bool
  /// Hard local-only switch. Nothing leaves the machine: no refinement, no AI
  /// commands. Overrides `refinementEnabled` rather than editing it, so turning
  /// privacy mode back off restores the user's previous choice.
  public var privacyMode: Bool
  public var historyEnabled: Bool
  public var historyLimit: Int
  /// Tone used when no rule matches the frontmost app.
  public var defaultTone: StyleTone
  /// Bundle identifier -> tone, from the Settings per-app list. Takes priority
  /// over the built-in table in `AppStyleResolver`.
  public var styleOverrides: [String: StyleTone]

  /// Hold to translate the selection, or what you say when nothing is selected.
  public var translateHotkey: Hotkey?
  /// Where translation lands, as a plain language name ("Spanish", "Japanese").
  /// Free text rather than an enum: the model handles any language, and a fixed
  /// list would be a maintenance burden that silently limits the feature.
  public var translationTargetLanguage: String
  /// Hold to ask a question, with the selection as context when there is one.
  public var askHotkey: Hotkey?
  /// Force every Ask AI result into the answer window. Off means the result is
  /// routed by `AskIntentClassifier`: a question opens the window, anything
  /// else is inserted at the cursor.
  public var askAlwaysOpensWindow: Bool

  public init(
    dictationHotkey: Hotkey,
    commandHotkey: Hotkey?,
    dictationActivationMode: DictationActivationMode,
    llmModel: String,
    refinementEnabled: Bool = true,
    privacyMode: Bool = false,
    historyEnabled: Bool = true,
    historyLimit: Int = TranscriptHistoryStore.defaultLimit,
    defaultTone: StyleTone = .neutral,
    styleOverrides: [String: StyleTone] = [:],
    translateHotkey: Hotkey? = nil,
    translationTargetLanguage: String = "",
    askHotkey: Hotkey? = nil,
    askAlwaysOpensWindow: Bool = false,
    dictationProvider: DictationProvider = .parakeet,
    openAITranscriptionModel: String = SpeechTranscriptionRequest.defaultOpenAIModel,
    openAITranscriptionFallbackEnabled: Bool = true
  ) {
    self.dictationHotkey = dictationHotkey
    self.commandHotkey = commandHotkey
    self.dictationActivationMode = dictationActivationMode
    self.llmModel = llmModel
    self.refinementEnabled = refinementEnabled
    self.privacyMode = privacyMode
    self.historyEnabled = historyEnabled
    self.historyLimit = historyLimit
    self.defaultTone = defaultTone
    self.styleOverrides = styleOverrides
    self.translateHotkey = translateHotkey
    self.translationTargetLanguage = translationTargetLanguage
    self.askHotkey = askHotkey
    self.askAlwaysOpensWindow = askAlwaysOpensWindow
    self.dictationProvider = dictationProvider
    self.openAITranscriptionModel = openAITranscriptionModel
    self.openAITranscriptionFallbackEnabled = openAITranscriptionFallbackEnabled
  }

  // Decoded field by field with defaults rather than synthesized, so settings
  // saved by an earlier build load instead of failing and silently resetting
  // the user's hotkeys back to stock.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    dictationHotkey = try container.decode(Hotkey.self, forKey: .dictationHotkey)
    commandHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .commandHotkey)
    dictationActivationMode = try container.decode(
      DictationActivationMode.self,
      forKey: .dictationActivationMode
    )
    llmModel = try container.decode(String.self, forKey: .llmModel)
    refinementEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .refinementEnabled) ?? true
    privacyMode =
      try container.decodeIfPresent(Bool.self, forKey: .privacyMode) ?? false
    historyEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? true
    historyLimit =
      try container.decodeIfPresent(Int.self, forKey: .historyLimit)
      ?? TranscriptHistoryStore.defaultLimit
    defaultTone =
      try container.decodeIfPresent(StyleTone.self, forKey: .defaultTone) ?? .neutral
    styleOverrides =
      try container.decodeIfPresent([String: StyleTone].self, forKey: .styleOverrides)
      ?? [:]
    translateHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .translateHotkey)
    translationTargetLanguage =
      try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? ""
    askHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .askHotkey)
    askAlwaysOpensWindow =
      try container.decodeIfPresent(Bool.self, forKey: .askAlwaysOpensWindow) ?? false
    dictationProvider =
      try container.decodeIfPresent(
        DictationProvider.self,
        forKey: .dictationProvider
      ) ?? .parakeet
    openAITranscriptionModel =
      try container.decodeIfPresent(
        String.self,
        forKey: .openAITranscriptionModel
      ) ?? SpeechTranscriptionRequest.defaultOpenAIModel
    openAITranscriptionFallbackEnabled =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .openAITranscriptionFallbackEnabled
      ) ?? true
  }

  public var dictationTranscriptionRequest: SpeechTranscriptionRequest {
    SpeechTranscriptionRequest(
      provider: dictationProvider,
      model: openAITranscriptionModel,
      fallbackToParakeet: openAITranscriptionFallbackEnabled
    )
  }

  /// Refinement runs whenever it is enabled and privacy mode is off. A blank
  /// model is passed through so the Codex CLI subscription default applies.
  public var isRefinementActive: Bool {
    refinementEnabled && !privacyMode
  }

  /// AI Commands need the network, so privacy mode disables them outright.
  public var areCommandsActive: Bool {
    commandHotkey != nil && !privacyMode
  }

  /// Translation needs a destination language.
  public var isTranslateActive: Bool {
    translateHotkey != nil
      && !privacyMode
      && !trimmed(translationTargetLanguage).isEmpty
  }

  public var isAskActive: Bool {
    askHotkey != nil && !privacyMode
  }

  /// The hotkey bound to each mode, for the global monitor.
  public func hotkey(for mode: MicAIMode) -> Hotkey? {
    switch mode {
    case .dictation:
      dictationHotkey
    case .command:
      commandHotkey
    case .translate:
      translateHotkey
    case .ask:
      askHotkey
    }
  }

  private func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func resolver() -> AppStyleResolver {
    AppStyleResolver(overrides: styleOverrides, defaultTone: defaultTone)
  }

  public func validated() throws -> AppSettings {
    let trimmedModel = trimmed(llmModel)
    let trimmedLanguage = trimmed(translationTargetLanguage)
    let llmModes: [Hotkey?] = [commandHotkey, translateHotkey, askHotkey]

    // Structural problems are reported before missing values. Binding two modes
    // to one chord while the language box happens to be empty is a collision,
    // and saying "enter a language" would send the user to fix the wrong field.
    //
    // Every configured hotkey must be distinct: two modes on one chord means
    // whichever the monitor happens to test first silently wins.
    let configured = [dictationHotkey] + llmModes.compactMap { $0 }
    guard Set(configured).count == configured.count else {
      throw AppSettingsValidationError.duplicateHotkeys
    }
    guard configured.allSatisfy(Self.isUsable) else {
      throw AppSettingsValidationError.unusableHotkey
    }

    if !privacyMode, translateHotkey != nil, trimmedLanguage.isEmpty {
      throw AppSettingsValidationError.emptyTargetLanguage
    }
    let trimmedTranscriptionModel = trimmed(openAITranscriptionModel)
    if dictationProvider == .openAI, trimmedTranscriptionModel.isEmpty {
      throw AppSettingsValidationError.emptyOpenAITranscriptionModel
    }

    var validatedSettings = self
    validatedSettings.llmModel = trimmedModel
    validatedSettings.translationTargetLanguage = trimmedLanguage
    validatedSettings.historyLimit = min(max(historyLimit, 1), 2_000)
    validatedSettings.openAITranscriptionModel = trimmedTranscriptionModel
    return validatedSettings
  }

  private enum CodingKeys: String, CodingKey {
    case dictationHotkey
    case commandHotkey
    case dictationActivationMode
    case llmModel
    case dictationProvider
    case openAITranscriptionModel
    case openAITranscriptionFallbackEnabled
    case refinementEnabled
    case privacyMode
    case historyEnabled
    case historyLimit
    case defaultTone
    case styleOverrides
    case translateHotkey
    case translationTargetLanguage
    case askHotkey
    case askAlwaysOpensWindow
  }

  /// Same rules as recording a shortcut in Settings, so a hand-edited or
  /// migrated preference cannot bind something the recorder would refuse.
  private static func isUsable(_ hotkey: Hotkey) -> Bool {
    HotkeyCapture.resolve(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers)
      == .success(hotkey)
  }
}

extension HotkeyModifier {
  fileprivate static let displayOrder: [HotkeyModifier] = [
    .control, .option, .shift, .command,
  ]

  fileprivate var symbol: String {
    switch self {
    case .command:
      "⌘"
    case .control:
      "⌃"
    case .option:
      "⌥"
    case .shift:
      "⇧"
    }
  }
}
