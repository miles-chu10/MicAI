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
  case emptyOpenAITranscriptionModel
  case duplicateHotkeys
  case unusableHotkey
}

extension AppSettingsValidationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyModel:
      "Enter an LLM model."
    case .emptyOpenAITranscriptionModel:
      "Enter an OpenAI transcription model."
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

  public init(
    dictationHotkey: Hotkey,
    commandHotkey: Hotkey?,
    dictationActivationMode: DictationActivationMode,
    llmModel: String,
    dictationProvider: DictationProvider = .parakeet,
    openAITranscriptionModel: String = SpeechTranscriptionRequest.defaultOpenAIModel,
    openAITranscriptionFallbackEnabled: Bool = true
  ) {
    self.dictationHotkey = dictationHotkey
    self.commandHotkey = commandHotkey
    self.dictationActivationMode = dictationActivationMode
    self.llmModel = llmModel
    self.dictationProvider = dictationProvider
    self.openAITranscriptionModel = openAITranscriptionModel
    self.openAITranscriptionFallbackEnabled = openAITranscriptionFallbackEnabled
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    dictationHotkey = try container.decode(Hotkey.self, forKey: .dictationHotkey)
    commandHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .commandHotkey)
    dictationActivationMode = try container.decode(
      DictationActivationMode.self,
      forKey: .dictationActivationMode
    )
    llmModel = try container.decode(String.self, forKey: .llmModel)
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

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(dictationHotkey, forKey: .dictationHotkey)
    try container.encodeIfPresent(commandHotkey, forKey: .commandHotkey)
    try container.encode(dictationActivationMode, forKey: .dictationActivationMode)
    try container.encode(llmModel, forKey: .llmModel)
    try container.encode(dictationProvider, forKey: .dictationProvider)
    try container.encode(openAITranscriptionModel, forKey: .openAITranscriptionModel)
    try container.encode(
      openAITranscriptionFallbackEnabled,
      forKey: .openAITranscriptionFallbackEnabled
    )
  }

  public var dictationTranscriptionRequest: SpeechTranscriptionRequest {
    SpeechTranscriptionRequest(
      provider: dictationProvider,
      model: openAITranscriptionModel,
      fallbackToParakeet: openAITranscriptionFallbackEnabled
    )
  }

  public func validated() throws -> AppSettings {
    let trimmedModel = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedTranscriptionModel =
      openAITranscriptionModel
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if commandHotkey != nil, trimmedModel.isEmpty {
      throw AppSettingsValidationError.emptyModel
    }
    if dictationProvider == .openAI, trimmedTranscriptionModel.isEmpty {
      throw AppSettingsValidationError.emptyOpenAITranscriptionModel
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
