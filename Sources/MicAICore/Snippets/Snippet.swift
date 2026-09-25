import Foundation

/// Text you insert by saying its trigger phrase: "my email signature", "office
/// address", "standard disclaimer".
public struct Snippet: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  /// What you say. Matched after normalisation, so case and punctuation the
  /// recognizer adds do not matter.
  public var trigger: String
  /// What gets inserted, exactly as written. Never sent to the model.
  public var text: String
  public var useCount: Int

  public init(id: UUID = UUID(), trigger: String, text: String, useCount: Int = 0) {
    self.id = id
    self.trigger = trigger
    self.text = text
    self.useCount = useCount
  }

  /// A trigger that normalises to nothing could never be spoken, and an empty
  /// expansion would insert nothing in place of what the user said.
  public var isUsable: Bool {
    !SnippetMatcher.normalize(trigger).isEmpty
      && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// Decides whether a finished dictation was a snippet trigger.
///
/// Only the whole utterance matches. Expanding a trigger found mid-sentence
/// would fire on ordinary speech ("send them my address" is not a request to
/// paste the address), and a dictation that silently turned into something
/// else is worse than one that needs to be said again.
public enum SnippetMatcher {
  public static func normalize(_ text: String) -> String {
    let stripped = text.lowercased().unicodeScalars.map { scalar -> Character in
      CharacterSet.punctuationCharacters.contains(scalar)
        || CharacterSet.symbols.contains(scalar)
        ? " " : Character(scalar)
    }
    return String(stripped)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  public static func match(_ transcript: String, in snippets: [Snippet]) -> Snippet? {
    let spoken = normalize(transcript)
    guard !spoken.isEmpty else {
      return nil
    }
    return snippets.first { $0.isUsable && normalize($0.trigger) == spoken }
  }
}
