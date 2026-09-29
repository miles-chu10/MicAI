import Foundation

/// The user's snippets, persisted beside vocabulary and history.
public actor SnippetStore {
  private let file: JSONCollectionFile<Snippet>
  private var snippets: [Snippet]

  public init(file url: URL) {
    self.file = JSONCollectionFile(url: url)
    self.snippets = []
  }

  public static func applicationSupport() throws -> SnippetStore {
    let file = try JSONCollectionFile<Snippet>.inApplicationSupport(named: "snippets.json")
    return SnippetStore(file: file.url)
  }

  public func load() {
    snippets = file.load()
  }

  public func all() -> [Snippet] {
    snippets
  }

  /// Adds a snippet, or replaces the text of the one with the same trigger.
  /// Two snippets that normalise to the same phrase could never both fire.
  public func upsert(_ snippet: Snippet) {
    guard snippet.isUsable else {
      return
    }
    let key = SnippetMatcher.normalize(snippet.trigger)
    if let index = snippets.firstIndex(where: { SnippetMatcher.normalize($0.trigger) == key }) {
      snippets[index].trigger = snippet.trigger
      snippets[index].text = snippet.text
    } else {
      snippets.append(snippet)
    }
    persist()
  }

  public func delete(snippetID: UUID) {
    snippets.removeAll { $0.id == snippetID }
    persist()
  }

  public func recordUse(snippetID: UUID) {
    guard let index = snippets.firstIndex(where: { $0.id == snippetID }) else {
      return
    }
    snippets[index].useCount += 1
    persist()
  }

  private func persist() {
    try? file.save(snippets)
  }
}
