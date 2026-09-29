import Foundation

/// How dictated text should read once it reaches its destination.
///
/// The tone is resolved from the frontmost application (see `AppStyleResolver`)
/// and handed to `RefinementEngine`, which turns it into prompt guidance. It is
/// deliberately a small closed set: every extra tone multiplies the ways a
/// refinement can surprise the user.
public enum StyleTone: String, Codable, CaseIterable, Sendable {
  /// Chat and messaging. Contractions, lowercase openers, no sign-off.
  case casual
  /// Email and documents read by colleagues or clients.
  case professional
  /// Code editors, terminals, and AI prompts. Precision over warmth.
  case technical
  /// Clean up the words, change nothing else.
  case neutral

  public var displayName: String {
    switch self {
    case .casual:
      "Casual"
    case .professional:
      "Professional"
    case .technical:
      "Technical"
    case .neutral:
      "Neutral"
    }
  }

  /// A one-line summary for Settings rows and the HUD badge.
  public var shortDescription: String {
    switch self {
    case .casual:
      "Chat and messaging"
    case .professional:
      "Email and documents"
    case .technical:
      "Code, terminals, and AI prompts"
    case .neutral:
      "Clean up only"
    }
  }

  /// The prompt fragment appended to the refinement instructions.
  ///
  /// Written as constraints rather than adjectives: "do not add a greeting"
  /// survives a model swap far better than "be casual".
  public var guidance: String {
    switch self {
    case .casual:
      """
      Target register: casual message. Use contractions. Keep it short. \
      Do not add a greeting or a sign-off. Do not add emoji that were not spoken. \
      Leave sentence fragments alone when they read naturally in chat.
      """
    case .professional:
      """
      Target register: professional written communication. Use complete sentences \
      and standard punctuation. Keep the speaker's own wording wherever it already \
      works. Do not add a greeting, a sign-off, or pleasantries that were not spoken.
      """
    case .technical:
      """
      Target register: technical writing. Prefer precise, literal phrasing. \
      Preserve identifiers, file paths, flags, and code-like tokens exactly as \
      spoken, including capitalization and punctuation. Do not soften or embellish.
      """
    case .neutral:
      """
      Target register: none. Remove disfluencies and fix punctuation only. \
      Do not adjust tone, formality, vocabulary, or sentence structure.
      """
    }
  }
}
