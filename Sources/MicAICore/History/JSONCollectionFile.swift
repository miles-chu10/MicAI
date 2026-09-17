import Foundation

/// A small JSON array on disk, written atomically.
///
/// Both the vocabulary and the history live in Application Support rather than
/// UserDefaults: they grow without bound, and a corrupt defaults plist would
/// take the app's settings down with it. A corrupt file here degrades to an
/// empty collection instead.
struct JSONCollectionFile<Element: Codable & Sendable>: Sendable {
  let url: URL

  /// `Application Support/MicAI/<name>`, creating the directory if needed.
  static func inApplicationSupport(named name: String) throws -> JSONCollectionFile {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = base.appendingPathComponent("MicAI", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return JSONCollectionFile(url: directory.appendingPathComponent(name))
  }

  /// Returns an empty array when the file is missing or unreadable. Losing
  /// history is an annoyance; refusing to dictate because of it is not.
  func load() -> [Element] {
    guard let data = try? Data(contentsOf: url) else {
      return []
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([Element].self, from: data)) ?? []
  }

  func save(_ elements: [Element]) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(elements)
    try data.write(to: url, options: [.atomic])
  }
}
