/// What a hotkey press is asking MicAI to do.
///
/// Every mode records audio and, except for plain dictation, captures the
/// current selection first. What differs is what happens to the transcript.
public enum MicAIMode: String, Codable, CaseIterable, Sendable {
  /// Speech becomes polished text at the cursor.
  case dictation
  /// Spoken instruction transforms the selection, or drafts in place.
  case command
  /// Selection, or speech when nothing is selected, comes back in another
  /// language.
  case translate
  /// A spoken question is answered. Content lands at the cursor; a question
  /// opens the answer in a window.
  case ask
  /// One of the user's own modes. Which one is carried alongside, since there
  /// can be any number.
  case custom

  /// The four modes MicAI ships with, for places that list them.
  public static let builtIn: [MicAIMode] = [.dictation, .command, .translate, .ask]

  public var displayName: String {
    switch self {
    case .dictation:
      "Dictation"
    case .command:
      "AI Command"
    case .translate:
      "AI Translate"
    case .ask:
      "Ask AI"
    case .custom:
      "Custom mode"
    }
  }

  /// True when the mode needs the frontmost app's selection before recording.
  public var capturesSelection: Bool {
    self != .dictation
  }
}
