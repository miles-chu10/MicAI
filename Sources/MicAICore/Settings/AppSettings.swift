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

public enum HotkeyModifier: String, Codable, CaseIterable, Sendable {
  case command
  case control
  case option
  case shift
}

public struct Hotkey: Codable, Equatable, Sendable {
  public static let rightOption = Hotkey(keyCode: 61)

  public var keyCode: UInt16
  public var modifiers: Set<HotkeyModifier>

  public init(keyCode: UInt16, modifiers: Set<HotkeyModifier> = []) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
}

public enum AppSettingsValidationError: Error, Equatable, Sendable {
  case emptyModel
  case duplicateHotkeys
}

extension AppSettingsValidationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyModel:
      "Enter an LLM model."
    case .duplicateHotkeys:
      "Dictation and command hotkeys must be different."
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

  public init(
    dictationHotkey: Hotkey,
    commandHotkey: Hotkey?,
    dictationActivationMode: DictationActivationMode,
    llmModel: String
  ) {
    self.dictationHotkey = dictationHotkey
    self.commandHotkey = commandHotkey
    self.dictationActivationMode = dictationActivationMode
    self.llmModel = llmModel
  }

  public func validated() throws -> AppSettings {
    let trimmedModel = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedModel.isEmpty else {
      throw AppSettingsValidationError.emptyModel
    }
    guard commandHotkey != dictationHotkey else {
      throw AppSettingsValidationError.duplicateHotkeys
    }

    var validatedSettings = self
    validatedSettings.llmModel = trimmedModel
    return validatedSettings
  }
}
