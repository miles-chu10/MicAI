import Foundation

public struct VocabularyApplication: Equatable, Sendable {
  public let text: String
  /// IDs of the entries that actually fired, so callers can bump hit counts.
  public let appliedEntryIDs: [UUID]

  public init(text: String, appliedEntryIDs: [UUID]) {
    self.text = text
    self.appliedEntryIDs = appliedEntryIDs
  }
}

/// Applies learned corrections to a transcript deterministically.
///
/// This runs before the LLM, not instead of it. Doing the substitution locally
/// means a proper noun is already correct even when refinement is off, the
/// network is down, or privacy mode is on — and the LLM then sees the corrected
/// spelling rather than being asked to guess at it.
public struct VocabularyApplier: Sendable {
  public init() {}

  public func apply(
    _ text: String,
    entries: [VocabularyEntry]
  ) -> VocabularyApplication {
    var result = text
    var appliedEntryIDs: [UUID] = []

    // Longest trigger first: "parakeet tdt" must win over "parakeet", otherwise
    // the shorter entry rewrites the prefix and the longer one stops matching.
    let usableEntries = entries
      .filter(\.isUsable)
      .sorted { $0.heard.count > $1.heard.count }

    for entry in usableEntries {
      let heard = entry.heard.trimmingCharacters(in: .whitespacesAndNewlines)
      let written = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
      let pattern = "\\b\(NSRegularExpression.escapedPattern(for: heard))\\b"
      guard
        let regex = try? NSRegularExpression(
          pattern: pattern,
          options: [.caseInsensitive]
        )
      else {
        continue
      }

      let range = NSRange(result.startIndex..<result.endIndex, in: result)
      guard regex.firstMatch(in: result, options: [], range: range) != nil else {
        continue
      }

      result = regex.stringByReplacingMatches(
        in: result,
        options: [],
        range: range,
        withTemplate: NSRegularExpression.escapedTemplate(for: written)
      )
      appliedEntryIDs.append(entry.id)
    }

    return VocabularyApplication(text: result, appliedEntryIDs: appliedEntryIDs)
  }

  /// The vocabulary as prompt context for the refinement pass.
  ///
  /// The local substitution above only catches exact word matches. Handing the
  /// same list to the model lets it fix inflections and near-misses the regex
  /// cannot see ("parakeets", "para keet"). Capped because this rides along on
  /// every single dictation request.
  public func promptContext(
    entries: [VocabularyEntry],
    limit: Int = 40
  ) -> String? {
    let usableEntries = entries
      .filter(\.isUsable)
      .sorted { $0.hitCount > $1.hitCount }
      .prefix(limit)
    guard !usableEntries.isEmpty else {
      return nil
    }

    let terms = usableEntries
      .map { "\"\($0.heard)\" -> \"\($0.written)\"" }
      .joined(separator: ", ")
    return
      "Known corrections for this speaker, apply when the audio clearly meant "
      + "the left-hand form: \(terms)."
  }
}
