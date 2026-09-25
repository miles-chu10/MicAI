import Foundation

public enum DictationActivationMode: String, Codable, CaseIterable, Sendable {
  case hold
  case toggle
  /// Hold to talk, or tap once to keep recording hands-free until the next
  /// press. Which one happened is decided on release, by how long the key was
  /// down, so neither gesture needs a timer or a second key.
  case hybrid

  public var displayName: String {
    switch self {
    case .hold:
      "Hold"
    case .toggle:
      "Toggle"
    case .hybrid:
      "Hold or tap"
    }
  }
}

/// Which service does the language work: clean-up, commands, translation and
/// answers. Speech recognition is always on-device regardless.
public enum LLMProvider: String, Codable, CaseIterable, Sendable {
  /// The ChatGPT sign-in Codex already stored on this Mac.
  case chatGPTSubscription
  /// An OpenAI platform API key, kept in the macOS Keychain.
  case openAIAPIKey

  public var displayName: String {
    switch self {
    case .chatGPTSubscription:
      "ChatGPT subscription"
    case .openAIAPIKey:
      "OpenAI API key"
    }
  }
}

/// Where dictation clean-up runs.
public enum CleanupEngine: String, Codable, CaseIterable, Sendable {
  /// The provider chosen for the AI modes: ChatGPT or an OpenAI API key.
  case languageModel
  /// Apple's on-device model (Apple Intelligence, macOS 26 or later). The
  /// transcript never leaves the Mac, so it keeps working in privacy mode.
  case onDevice

  public var displayName: String {
    switch self {
    case .languageModel:
      "Your language model"
    case .onDevice:
      "Apple Intelligence, on this Mac"
    }
  }
}

/// Which refiner a dictation goes through, once settings are taken into
/// account. Nil means the transcript goes in as recognised.
public enum RefinementRoute: Sendable, Equatable {
  case languageModel
  case onDevice
}

/// The on-device Parakeet model. Both run locally; they trade language coverage
/// for English accuracy.
public enum SpeechModelChoice: String, Codable, CaseIterable, Sendable {
  /// Parakeet TDT v2: English only, the most accurate for English.
  case english
  /// Parakeet TDT v3: 25 European languages, detected automatically.
  case multilingual

  public var displayName: String {
    switch self {
    case .english:
      "English"
    case .multilingual:
      "Multilingual"
    }
  }

  public var detail: String {
    switch self {
    case .english:
      "Parakeet TDT v2. Best accuracy for English."
    case .multilingual:
      "Parakeet TDT v3. 25 European languages, detected as you speak."
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

  /// Virtual key codes to labels. Values are Carbon `kVK_*` constants, labelled
  /// as on a US ANSI keyboard, which is how macOS itself names shortcut keys in
  /// most places. Anything unlisted falls back to its number.
  static let keyNames: [UInt16: String] = [
    0: "A",
    1: "S",
    2: "D",
    3: "F",
    4: "H",
    5: "G",
    6: "Z",
    7: "X",
    8: "C",
    9: "V",
    11: "B",
    12: "Q",
    13: "W",
    14: "E",
    15: "R",
    16: "Y",
    17: "T",
    18: "1",
    19: "2",
    20: "3",
    21: "4",
    22: "6",
    23: "5",
    24: "=",
    25: "9",
    26: "7",
    27: "-",
    28: "8",
    29: "0",
    30: "]",
    31: "O",
    32: "U",
    33: "[",
    34: "I",
    35: "P",
    36: "Return",
    37: "L",
    38: "J",
    39: "'",
    40: "K",
    41: ";",
    42: "\\",
    43: ",",
    44: "/",
    45: "N",
    46: "M",
    47: ".",
    48: "Tab",
    49: "Space",
    50: "`",
    96: "F5",
    97: "F6",
    98: "F7",
    99: "F3",
    100: "F8",
    101: "F9",
    103: "F11",
    109: "F10",
    111: "F12",
    118: "F4",
    120: "F2",
    122: "F1",
  ]

  /// Keys a recorded shortcut may not use: Escape cancels every operation, and
  /// Delete and Forward Delete edit text.
  public static let reservedKeyCodes: Set<UInt16> = [51, 53, 117]

  /// The shortcut a key press would record, or nil when it cannot be one.
  ///
  /// It needs Control, Option or Command. Shift alone is not enough: MicAI
  /// listens to keys without consuming them, so Shift-A would fire every time
  /// you typed a capital A.
  public static func recordable(keyCode: UInt16, modifiers: Set<HotkeyModifier>) -> Hotkey? {
    guard !reservedKeyCodes.contains(keyCode),
      !modifiers.isDisjoint(with: [.control, .option, .command])
    else {
      return nil
    }
    return Hotkey(keyCode: keyCode, modifiers: modifiers)
  }

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

  /// One label per physical key, in the order macOS menus print them, for
  /// drawing keycaps.
  public var keyCaps: [String] {
    if self == .rightOption {
      return ["Right ⌥"]
    }
    let modifierNames = HotkeyModifier.displayOrder.compactMap { modifier in
      modifiers.contains(modifier) ? modifier.symbol : nil
    }
    return modifierNames + [Self.keyNames[keyCode] ?? "Key \(keyCode)"]
  }
}

public enum AppSettingsValidationError: Error, Equatable, Sendable {
  case emptyModel
  case duplicateHotkeys
  case unusableHotkey
  case emptyTargetLanguage
  case incompleteCustomMode
}

extension AppSettingsValidationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyModel:
      "Enter an LLM model."
    case .duplicateHotkeys:
      "Each mode needs its own shortcut."
    case .unusableHotkey:
      "Choose a supported hotkey with modifiers."
    case .emptyTargetLanguage:
      "Enter a language to translate into."
    case .incompleteCustomMode:
      "Give each custom mode a name and instructions."
    }
  }
}

public struct AppSettings: Codable, Equatable, Sendable {
  public static let defaults = AppSettings(
    dictationHotkey: .rightOption,
    commandHotkey: nil,
    dictationActivationMode: .hold,
    llmModel: ""
  )

  public var dictationHotkey: Hotkey
  public var commandHotkey: Hotkey?
  public var dictationActivationMode: DictationActivationMode
  public var llmModel: String

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

  /// Which service does the language work.
  public var llmProvider: LLMProvider
  /// Which on-device recognizer to load.
  public var speechModel: SpeechModelChoice
  /// Extra rules the user wants every clean-up to follow ("Use British
  /// spelling", "Never use exclamation marks"). Appended to the tone guidance.
  public var customInstructions: String
  /// Play the system sounds for start, finish and failure.
  public var soundFeedback: Bool
  /// Where clean-up runs.
  public var cleanupEngine: CleanupEngine
  /// Show a rough transcript above the HUD while recording.
  public var livePreview: Bool
  /// The user's own modes, in the order Settings lists them.
  public var customModes: [CustomMode]

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
    llmProvider: LLMProvider = .chatGPTSubscription,
    speechModel: SpeechModelChoice = .english,
    customInstructions: String = "",
    soundFeedback: Bool = true,
    cleanupEngine: CleanupEngine = .languageModel,
    livePreview: Bool = true,
    customModes: [CustomMode] = []
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
    self.llmProvider = llmProvider
    self.speechModel = speechModel
    self.customInstructions = customInstructions
    self.soundFeedback = soundFeedback
    self.cleanupEngine = cleanupEngine
    self.livePreview = livePreview
    self.customModes = customModes
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
    llmProvider =
      try container.decodeIfPresent(LLMProvider.self, forKey: .llmProvider)
      ?? .chatGPTSubscription
    speechModel =
      try container.decodeIfPresent(SpeechModelChoice.self, forKey: .speechModel)
      ?? .english
    customInstructions =
      try container.decodeIfPresent(String.self, forKey: .customInstructions) ?? ""
    soundFeedback =
      try container.decodeIfPresent(Bool.self, forKey: .soundFeedback) ?? true
    cleanupEngine =
      try container.decodeIfPresent(CleanupEngine.self, forKey: .cleanupEngine)
      ?? .languageModel
    livePreview =
      try container.decodeIfPresent(Bool.self, forKey: .livePreview) ?? true
    customModes =
      try container.decodeIfPresent([CustomMode].self, forKey: .customModes) ?? []
  }

  /// Refinement runs only with a model configured and privacy mode off.
  /// An empty model is not a validation error — it degrades to raw dictation.
  public var isRefinementActive: Bool {
    refinementEnabled
      && !privacyMode
      && !llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Which refiner a dictation uses, or nil to insert it as recognised.
  ///
  /// On-device clean-up ignores privacy mode and the model name: nothing
  /// leaves the Mac, and there is no model to choose.
  public var refinementRoute: RefinementRoute? {
    guard refinementEnabled else {
      return nil
    }
    switch cleanupEngine {
    case .onDevice:
      return .onDevice
    case .languageModel:
      return isRefinementActive ? .languageModel : nil
    }
  }

  /// AI Commands need the network, so privacy mode disables them outright.
  public var areCommandsActive: Bool {
    commandHotkey != nil && !privacyMode
  }

  /// Translation needs the model and a destination language.
  public var isTranslateActive: Bool {
    translateHotkey != nil
      && !privacyMode
      && !trimmed(llmModel).isEmpty
      && !trimmed(translationTargetLanguage).isEmpty
  }

  /// Custom modes use the language model, so they share its requirements.
  public var areCustomModesActive: Bool {
    !privacyMode && !trimmed(llmModel).isEmpty
  }

  public func customMode(id: UUID) -> CustomMode? {
    customModes.first { $0.id == id }
  }

  public var isAskActive: Bool {
    askHotkey != nil && !privacyMode && !trimmed(llmModel).isEmpty
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
    case .custom:
      // Each custom mode has its own shortcut; see `customModes`.
      nil
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
    let llmModes: [Hotkey?] =
      [commandHotkey, translateHotkey, askHotkey] + customModes.map(\.hotkey)

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

    guard customModes.allSatisfy(\.isComplete) else {
      throw AppSettingsValidationError.incompleteCustomMode
    }
    if !privacyMode, trimmedModel.isEmpty, llmModes.contains(where: { $0 != nil }) {
      throw AppSettingsValidationError.emptyModel
    }
    if !privacyMode, translateHotkey != nil, trimmedLanguage.isEmpty {
      throw AppSettingsValidationError.emptyTargetLanguage
    }

    var validatedSettings = self
    validatedSettings.llmModel = trimmedModel
    validatedSettings.translationTargetLanguage = trimmedLanguage
    validatedSettings.customInstructions = trimmed(customInstructions)
    validatedSettings.historyLimit = min(max(historyLimit, 1), 2_000)
    return validatedSettings
  }

  private static func isUsable(_ hotkey: Hotkey) -> Bool {
    hotkey == .rightOption || !hotkey.modifiers.isEmpty
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
