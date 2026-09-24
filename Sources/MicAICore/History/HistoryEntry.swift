import Foundation

/// One completed dictation or command, kept on disk so the user can recover
/// text that went into the wrong window, and correct terms after the fact.
public struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let createdAt: Date
  public let mode: MicAIMode
  /// What the recognizer produced, after deterministic cleanup but before
  /// vocabulary substitution and refinement. Kept so a correction can be
  /// diffed against what was actually heard.
  public let rawTranscript: String
  /// What was inserted into the target application.
  public var finalText: String
  public let applicationName: String?
  public let bundleIdentifier: String?
  public let tone: StyleTone?
  public let audioDuration: TimeInterval
  /// False when refinement was skipped — disabled, privacy mode, or failed.
  public let refined: Bool

  public init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    mode: MicAIMode,
    rawTranscript: String,
    finalText: String,
    applicationName: String? = nil,
    bundleIdentifier: String? = nil,
    tone: StyleTone? = nil,
    audioDuration: TimeInterval = 0,
    refined: Bool = false
  ) {
    self.id = id
    self.createdAt = createdAt
    self.mode = mode
    self.rawTranscript = rawTranscript
    self.finalText = finalText
    self.applicationName = applicationName
    self.bundleIdentifier = bundleIdentifier
    self.tone = tone
    self.audioDuration = audioDuration
    self.refined = refined
  }

  /// Single-line preview for the history list.
  public var preview: String {
    finalText
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
