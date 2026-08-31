public enum ReadinessBlocker: String, Sendable, Equatable, CaseIterable {
  case microphone
  case accessibility
  case speechModel
  case dictationProvider
  case commandHotkey
  case languageModel
  case activeOperation
  case recoveryPending

  public var message: String {
    switch self {
    case .microphone:
      "Allow Microphone access."
    case .accessibility:
      "Allow Accessibility access."
    case .speechModel:
      "Prepare the local speech model."
    case .dictationProvider:
      "Configure OpenAI transcription or enable the Parakeet fallback."
    case .commandHotkey:
      "Choose an AI Command hotkey."
    case .languageModel:
      "Enter the ChatGPT model used for commands."
    case .activeOperation:
      "Wait for the current operation to finish."
    case .recoveryPending:
      "Retry, copy, or dismiss the saved result."
    }
  }
}

public struct FeatureReadiness: Sendable, Equatable {
  public let blockers: [ReadinessBlocker]

  public init(blockers: [ReadinessBlocker]) {
    self.blockers = blockers
  }

  public var isReady: Bool {
    blockers.isEmpty
  }

  public var setupBlockers: [ReadinessBlocker] {
    blockers.filter {
      $0 != .activeOperation && $0 != .recoveryPending
    }
  }

  public var isSetupReady: Bool {
    setupBlockers.isEmpty
  }

  public var isBusy: Bool {
    blockers.contains(.activeOperation)
  }

  public var hasPendingRecovery: Bool {
    blockers.contains(.recoveryPending)
  }
}

public struct AppReadiness: Sendable, Equatable {
  public let dictation: FeatureReadiness
  public let command: FeatureReadiness

  public init(
    microphoneGranted: Bool,
    accessibilityGranted: Bool,
    speechModelReady: Bool,
    commandHotkeyConfigured: Bool,
    languageModelConfigured: Bool,
    operationActive: Bool,
    recoveryPending: Bool = false,
    dictationProvider: DictationProvider = .parakeet,
    openAITranscriptionConfigured: Bool = false,
    dictationFallbackEnabled: Bool = true
  ) {
    var common: [ReadinessBlocker] = []
    if !microphoneGranted {
      common.append(.microphone)
    }
    if !accessibilityGranted {
      common.append(.accessibility)
    }

    var dictationBlockers = common
    switch dictationProvider {
    case .parakeet:
      if !speechModelReady {
        dictationBlockers.append(.speechModel)
      }
    case .openAI:
      if dictationFallbackEnabled {
        if !speechModelReady {
          dictationBlockers.append(.speechModel)
        }
      } else if !openAITranscriptionConfigured {
        dictationBlockers.append(.dictationProvider)
      }
    }

    var commandBlockers = common
    if !speechModelReady {
      commandBlockers.append(.speechModel)
    }

    if operationActive {
      dictationBlockers.append(.activeOperation)
      commandBlockers.append(.activeOperation)
    }
    if recoveryPending {
      dictationBlockers.append(.recoveryPending)
      commandBlockers.append(.recoveryPending)
    }
    if !commandHotkeyConfigured {
      commandBlockers.append(.commandHotkey)
    }
    if !languageModelConfigured {
      commandBlockers.append(.languageModel)
    }

    dictation = FeatureReadiness(blockers: dictationBlockers)
    command = FeatureReadiness(blockers: commandBlockers)
  }
}
