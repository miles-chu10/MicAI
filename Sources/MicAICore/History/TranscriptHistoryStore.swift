import Foundation

/// On-device history of completed operations, newest first.
///
/// Nothing here ever leaves the machine. The cap is enforced on every write so
/// the file cannot grow without bound across months of use.
public actor TranscriptHistoryStore {
  public static let defaultLimit = 200

  private let file: JSONCollectionFile<HistoryEntry>
  private let limit: Int
  private var entries: [HistoryEntry]

  public init(file url: URL, limit: Int = TranscriptHistoryStore.defaultLimit) {
    self.file = JSONCollectionFile(url: url)
    self.limit = max(1, limit)
    self.entries = []
  }

  public static func applicationSupport(
    limit: Int = TranscriptHistoryStore.defaultLimit
  ) throws -> TranscriptHistoryStore {
    let file = try JSONCollectionFile<HistoryEntry>.inApplicationSupport(
      named: "history.json"
    )
    return TranscriptHistoryStore(file: file.url, limit: limit)
  }

  /// Reads the file once per process. Call before the first `all()`.
  public func load() {
    entries = file.load().sorted { $0.createdAt > $1.createdAt }
    trimAndPersist()
  }

  public func all() -> [HistoryEntry] {
    entries
  }

  public func record(_ entry: HistoryEntry) {
    entries.insert(entry, at: 0)
    trimAndPersist()
  }

  /// Applies a user edit and returns the vocabulary this correction implies.
  /// The caller decides whether to keep those proposals.
  @discardableResult
  public func correct(
    entryID: UUID,
    to correctedText: String,
    learner: VocabularyLearner = VocabularyLearner()
  ) -> [VocabularyEntry] {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
      return []
    }

    let original = entries[index].rawTranscript
    entries[index].finalText = correctedText
    trimAndPersist()
    return learner.proposals(original: original, corrected: correctedText)
  }

  public func delete(entryID: UUID) {
    entries.removeAll { $0.id == entryID }
    trimAndPersist()
  }

  /// Wipes history. Bound to the Settings "Clear history" button and invoked
  /// automatically when the user turns history off.
  public func clear() {
    entries.removeAll()
    trimAndPersist()
  }

  private func trimAndPersist() {
    if entries.count > limit {
      entries.removeSubrange(limit...)
    }
    try? file.save(entries)
  }
}
