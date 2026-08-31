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

public enum LLMProvider: String, Codable, CaseIterable, Sendable {
  case openAIAPIKey
  case chatGPTSubscription

  public var displayName: String {
    switch self {
    case .openAIAPIKey:
      "OpenAI API key"
    case .chatGPTSubscription:
      "ChatGPT subscription"
    }
  }

  public var modelFieldLabel: String {
    switch self {
    case .openAIAPIKey:
      "OpenAI model"
    case .chatGPTSubscription:
      "ChatGPT model"
    }
  }

  public var modelPlaceholder: String {
    switch self {
    case .openAIAPIKey:
      "Enter an OpenAI API model, e.g. gpt-5.4"
    case .chatGPTSubscription:
      "Enter a supported subscription model"
    }
  }
}

public struct AppSettings: Codable, Equatable, Sendable {
  public static let defaults = AppSettings(
    dictationHotkey: .rightOption,
    commandHotkey: nil,
    dictationActivationMode: .hold,
    llmProvider: .openAIAPIKey,
    llmModel: ""
  )

  public var dictationHotkey: Hotkey
  public var commandHotkey: Hotkey?
  public var dictationActivationMode: DictationActivationMode
  public var llmProvider: LLMProvider
  public var llmModel: String

  public init(
    dictationHotkey: Hotkey,
    commandHotkey: Hotkey?,
    dictationActivationMode: DictationActivationMode,
    llmProvider: LLMProvider = .openAIAPIKey,
    llmModel: String
  ) {
    self.dictationHotkey = dictationHotkey
    self.commandHotkey = commandHotkey
    self.dictationActivationMode = dictationActivationMode
    self.llmProvider = llmProvider
    self.llmModel = llmModel
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    dictationHotkey = try container.decode(Hotkey.self, forKey: .dictationHotkey)
    commandHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .commandHotkey)
    dictationActivationMode = try container.decode(
      DictationActivationMode.self,
      forKey: .dictationActivationMode
    )
    llmProvider =
      try container.decodeIfPresent(LLMProvider.self, forKey: .llmProvider)
      ?? .openAIAPIKey
    llmModel = try container.decode(String.self, forKey: .llmModel)
  }

  public func validated() throws -> AppSettings {
    let trimmedModel = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if commandHotkey != nil, trimmedModel.isEmpty {
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
