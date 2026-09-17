import Foundation

/// Where an Ask AI result should go.
public enum AskDestination: String, Codable, Sendable, Equatable {
  /// The result is content the user wants typed where they were typing.
  case insertAtCursor
  /// The result is an answer to read, so it opens in a window instead of being
  /// pasted into whatever had focus.
  case answerWindow
}

/// Decides whether what the user said was a question to answer or content to
/// write, from the utterance alone.
///
/// Deliberately a local heuristic rather than asking the model to classify: the
/// routing decides whether text lands in the user's Slack message box, so it has
/// to be predictable and testable. A model that classifies differently on two
/// identical utterances would make the hotkey feel broken.
public struct AskIntentClassifier: Sendable {
  /// Words that open a question. Matched on the first token only -- "what" mid
  /// sentence ("send them what we agreed") is not a question.
  static let interrogatives: Set<String> = [
    "what", "whats", "why", "how", "when", "where", "who", "whom", "whose",
    "which", "is", "are", "was", "were", "do", "does", "did", "can", "could",
    "should", "would", "will", "shall", "has", "have", "had", "am", "may",
    "might", "explain", "define",
  ]

  public init() {}

  public func destination(for spokenText: String) -> AskDestination {
    let trimmed = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .answerWindow
    }

    // Parakeet does emit question marks, but not reliably, so the leading-word
    // test below carries most of the weight.
    if trimmed.hasSuffix("?") {
      return .answerWindow
    }

    let words = trimmed.split(whereSeparator: { $0.isWhitespace })
    guard let first = words.first else {
      return .insertAtCursor
    }
    guard Self.interrogatives.contains(Self.normalize(first)) else {
      return .insertAtCursor
    }
    return .answerWindow
  }

  /// Lowercases and strips the punctuation a transcript may carry, including the
  /// typographic apostrophe: recognizers emit both forms of "what's", and only
  /// the stripped "whats" is in the table.
  static func normalize(_ word: some StringProtocol) -> String {
    var lowered = word.lowercased()
    lowered = lowered.replacingOccurrences(of: "'", with: "")
    lowered = lowered.replacingOccurrences(of: "\u{2019}", with: "")
    return lowered.trimmingCharacters(in: CharacterSet.punctuationCharacters)
  }
}
