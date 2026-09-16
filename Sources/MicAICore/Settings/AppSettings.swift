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
    let keyName = keyCode == 49 ? "Space" : "Key \(keyCode)"
    return modifierNames.joined() + keyName
  }
}

public enum AppSettingsValidationError: Error, Equatable, Sendable {
  case emptyModel
  case duplicateHotkeys
  case unusableHotkey
}

extension AppSettingsValidationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyModel:
      "Enter an LLM model."
    case .duplicateHotkeys:
      "Dictation and command hotkeys must be different."
    case .unusableHotkey:
      "Choose a supported hotkey with modifiers."
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
    styleOverrides: [String: StyleTone] = [:]
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
  }

  /// Refinement runs only with a model configured and privacy mode off.
  /// An empty model is not a validation error — it degrades to raw dictation.
  public var isRefinementActive: Bool {
    refinementEnabled
      && !privacyMode
      && !llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// AI Commands need the network, so privacy mode disables them outright.
  public var areCommandsActive: Bool {
    commandHotkey != nil && !privacyMode
  }

  public func resolver() -> AppStyleResolver {
    AppStyleResolver(overrides: styleOverrides, defaultTone: defaultTone)
  }

  public func validated() throws -> AppSettings {
    let trimmedModel = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if commandHotkey != nil, !privacyMode, trimmedModel.isEmpty {
      throw AppSettingsValidationError.emptyModel
    }
    guard commandHotkey != dictationHotkey else {
      throw AppSettingsValidationError.duplicateHotkeys
    }
    guard Self.isUsable(dictationHotkey),
      commandHotkey.map(Self.isUsable) ?? true
    else {
      throw AppSettingsValidationError.unusableHotkey
    }

    var validatedSettings = self
    validatedSettings.llmModel = trimmedModel
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
