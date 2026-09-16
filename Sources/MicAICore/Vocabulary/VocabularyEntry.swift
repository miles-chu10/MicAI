import Foundation

/// One learned correction: what the recognizer heard, and what it should say.
///
/// Entries come from two places — typed directly in Settings, or derived from
/// an edit the user made to a history entry (see `VocabularyLearner`).
public struct VocabularyEntry: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  /// The text as the recognizer produced it, e.g. "paraquet".
  public var heard: String
  /// The text the user wants instead, e.g. "Parakeet".
  public var written: String
  public var createdAt: Date
  /// How many times the substitution has fired. Surfaced in Settings so dead
  /// entries are easy to spot and delete.
  public var hitCount: Int

  public init(
    id: UUID = UUID(),
    heard: String,
    written: String,
    createdAt: Date = Date(),
    hitCount: Int = 0
  ) {
    self.id = id
    self.heard = heard
    self.written = written
    self.createdAt = createdAt
    self.hitCount = hitCount
  }

  /// An entry is usable only if it has a non-empty trigger and actually changes
  /// something. A no-op entry would burn a regex pass on every dictation.
  public var isUsable: Bool {
    let trimmedHeard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedWritten = written.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedHeard.isEmpty, !trimmedWritten.isEmpty else {
      return false
    }
    return trimmedHeard.caseInsensitiveCompare(trimmedWritten) != .orderedSame
  }
}
