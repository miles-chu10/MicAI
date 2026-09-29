import Foundation

/// Derives vocabulary candidates from a correction the user made by hand.
///
/// This is the "fix it once" path: the user edits a history entry, and the
/// words they changed become proposed `VocabularyEntry` values. Proposals are
/// returned rather than saved — a silent store that learns from every keystroke
/// would accumulate garbage from ordinary rewording.
public struct VocabularyLearner: Sendable {
  /// Replacement blocks longer than this are rewording, not a misheard term.
  public static let maximumPhraseWords = 3

  public init() {}

  public func proposals(
    original: String,
    corrected: String
  ) -> [VocabularyEntry] {
    let originalWords = Self.words(in: original)
    let correctedWords = Self.words(in: corrected)
    guard !originalWords.isEmpty, !correctedWords.isEmpty else {
      return []
    }

    var proposals: [VocabularyEntry] = []
    for block in Self.replacementBlocks(from: originalWords, to: correctedWords) {
      guard
        block.original.count <= Self.maximumPhraseWords,
        block.corrected.count <= Self.maximumPhraseWords
      else {
        continue
      }

      let entry = VocabularyEntry(
        heard: block.original.joined(separator: " "),
        written: block.corrected.joined(separator: " ")
      )
      if entry.isUsable {
        proposals.append(entry)
      }
    }
    return proposals
  }

  // MARK: - Word diff

  struct ReplacementBlock: Equatable {
    let original: [String]
    let corrected: [String]
  }

  /// Splits on whitespace and drops surrounding punctuation, so "Parakeet."
  /// and "Parakeet" produce one proposal rather than two.
  static func words(in text: String) -> [String] {
    text
      .split(whereSeparator: \.isWhitespace)
      .map { word in
        word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
      }
      .filter { !$0.isEmpty }
  }

  /// Walks an LCS alignment and collects the spans that differ on both sides.
  /// A span present on only one side is an insertion or deletion — the user
  /// adding or cutting words — which teaches nothing about pronunciation.
  static func replacementBlocks(
    from original: [String],
    to corrected: [String]
  ) -> [ReplacementBlock] {
    let table = lcsTable(original, corrected)
    var blocks: [ReplacementBlock] = []
    var pendingOriginal: [String] = []
    var pendingCorrected: [String] = []

    func flush() {
      if !pendingOriginal.isEmpty, !pendingCorrected.isEmpty {
        blocks.append(
          ReplacementBlock(original: pendingOriginal, corrected: pendingCorrected)
        )
      }
      pendingOriginal.removeAll()
      pendingCorrected.removeAll()
    }

    var i = 0
    var j = 0
    while i < original.count, j < corrected.count {
      if original[i].compare(corrected[j], options: .caseInsensitive) == .orderedSame {
        flush()
        i += 1
        j += 1
      } else if table[i + 1][j] >= table[i][j + 1] {
        pendingOriginal.append(original[i])
        i += 1
      } else {
        pendingCorrected.append(corrected[j])
        j += 1
      }
    }
    pendingOriginal.append(contentsOf: original[i...])
    pendingCorrected.append(contentsOf: corrected[j...])
    flush()

    return blocks
  }

  private static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
    var table = Array(
      repeating: Array(repeating: 0, count: b.count + 1),
      count: a.count + 1
    )
    guard !a.isEmpty, !b.isEmpty else {
      return table
    }

    for i in stride(from: a.count - 1, through: 0, by: -1) {
      for j in stride(from: b.count - 1, through: 0, by: -1) {
        if a[i].compare(b[j], options: .caseInsensitive) == .orderedSame {
          table[i][j] = table[i + 1][j + 1] + 1
        } else {
          table[i][j] = max(table[i + 1][j], table[i][j + 1])
        }
      }
    }
    return table
  }
}
