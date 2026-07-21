import Foundation

public protocol TranscriptCleaning: Sendable {
  func clean(_ text: String) -> String
}

public struct TranscriptCleaner: TranscriptCleaning, Sendable {
  public init() {}

  public func clean(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n?", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "[\t ]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
