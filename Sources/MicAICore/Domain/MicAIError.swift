import Foundation

public enum MicAIError: Error, Equatable, Sendable {
  case operationAlreadyActive
  case invalidTransition
  case cancelled
}

extension MicAIError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .operationAlreadyActive:
      "Another operation is already active."
    case .invalidTransition:
      "The operation cannot move to the requested phase."
    case .cancelled:
      "The operation was cancelled."
    }
  }
}
