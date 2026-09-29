import Foundation

/// The user's learned corrections, persisted to disk.
public actor VocabularyStore {
  private let file: JSONCollectionFile<VocabularyEntry>
  private var entries: [VocabularyEntry]

  public init(file url: URL) {
    self.file = JSONCollectionFile(url: url)
    self.entries = []
  }

  public static func applicationSupport() throws -> VocabularyStore {
    let file = try JSONCollectionFile<VocabularyEntry>.inApplicationSupport(
      named: "vocabulary.json"
    )
    return VocabularyStore(file: file.url)
  }

  public func load() {
    entries = file.load()
  }

  public func all() -> [VocabularyEntry] {
    entries
  }

  /// Adds an entry, or updates the replacement when the trigger already exists.
  /// Matching on `heard` case-insensitively keeps the list from filling up with
  /// "Parakeet"/"parakeet" duplicates that would both fire on the same word.
  public func upsert(_ entry: VocabularyEntry) {
    guard entry.isUsable else {
      return
    }

    if let index = entries.firstIndex(where: {
      $0.heard.caseInsensitiveCompare(entry.heard) == .orderedSame
    }) {
      entries[index].written = entry.written
    } else {
      entries.append(entry)
    }
    persist()
  }

  public func delete(entryID: UUID) {
    entries.removeAll { $0.id == entryID }
    persist()
  }

  /// Bumps usage counts after an applier run, so Settings can sort by what is
  /// actually earning its place.
  public func recordHits(entryIDs: [UUID]) {
    guard !entryIDs.isEmpty else {
      return
    }

    let hitIDs = Set(entryIDs)
    for index in entries.indices where hitIDs.contains(entries[index].id) {
      entries[index].hitCount += 1
    }
    persist()
  }

  private func persist() {
    try? file.save(entries)
  }
}
