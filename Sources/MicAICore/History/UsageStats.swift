import Foundation

/// What dictation has saved you, computed from history on this Mac.
///
/// Nothing here is tracked separately: the numbers are derived from the
/// entries history already keeps, so turning history off or clearing it also
/// clears the stats, and no counter can drift from what the list shows.
public struct UsageStats: Equatable, Sendable {
  /// Words per minute used as the typing baseline. A commonly cited average for
  /// adults typing on a keyboard; it is a yardstick, not a measurement of you.
  public static let typingWordsPerMinute: Double = 40
  /// Below this much audio, a speaking rate would be noise.
  public static let minimumAudioForRate: TimeInterval = 5

  public let entryCount: Int
  public let wordCount: Int
  public let audioSeconds: TimeInterval

  public init(entries: [HistoryEntry], since start: Date? = nil) {
    let included = entries.filter { entry in
      guard let start else {
        return true
      }
      return entry.createdAt >= start
    }
    entryCount = included.count
    wordCount = included.reduce(0) { $0 + Self.wordCount(in: $1.finalText) }
    audioSeconds = included.reduce(0) { $0 + max($1.audioDuration, 0) }
  }

  /// Speaking rate across the included entries, or nil with too little audio
  /// to say anything meaningful.
  public var wordsPerMinute: Int? {
    guard audioSeconds >= Self.minimumAudioForRate else {
      return nil
    }
    return Int((Double(wordCount) / (audioSeconds / 60)).rounded())
  }

  /// Minutes it would have taken to type the same words, less the minutes
  /// spent speaking them. Never negative: a slow dictation saved nothing, it
  /// did not cost typing time.
  public var minutesSaved: Double {
    let typing = Double(wordCount) / Self.typingWordsPerMinute
    return max(typing - audioSeconds / 60, 0)
  }

  static func wordCount(in text: String) -> Int {
    var count = 0
    text.enumerateSubstrings(
      in: text.startIndex..<text.endIndex,
      options: [.byWords, .localized, .substringNotRequired]
    ) { _, _, _, _ in
      count += 1
    }
    return count
  }
}
