public enum ReadinessBlocker: String, Sendable, Equatable, CaseIterable {
  case microphone
  case accessibility
  case speechModel
  case commandHotkey
  case languageModel
  case activeOperation

  public var message: String {
    switch self {
    case .microphone:
      "Allow Microphone access."
    case .accessibility:
      "Allow Accessibility access."
    case .speechModel:
      "Prepare the local speech model."
    case .commandHotkey:
      "Choose an AI Command hotkey."
    case .languageModel:
      "Enter the model used for commands."
    case .activeOperation:
      "Wait for the current operation to finish."
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
    operationActive: Bool
  ) {
    var shared: [ReadinessBlocker] = []
    if !microphoneGranted {
      shared.append(.microphone)
    }
    if !accessibilityGranted {
      shared.append(.accessibility)
    }
    if !speechModelReady {
      shared.append(.speechModel)
    }
    if operationActive {
      shared.append(.activeOperation)
    }

    var commandBlockers = shared
    if !commandHotkeyConfigured {
      commandBlockers.append(.commandHotkey)
    }
    if !languageModelConfigured {
      commandBlockers.append(.languageModel)
    }

    dictation = FeatureReadiness(blockers: shared)
    command = FeatureReadiness(blockers: commandBlockers)
  }
}
