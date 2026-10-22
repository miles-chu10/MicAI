/// Keeps finished text that an operation was about to insert, so a failed
/// insertion (focus moved, Accessibility revoked, paste refused) never loses
/// a dictation or a model answer. Recovering it is a plain paste or copy of
/// the kept text: no model call is repeated.
public struct InsertionRecovery: Sendable, Equatable {
  public static let hint =
    "Your text is kept: use Paste Last Result or Copy Last Result in the MicAI menu."

  public private(set) var pendingText: String?

  public init() {}

  /// Call once the text is final and insertion is about to start.
  public mutating func prepare(_ text: String) {
    pendingText = text
  }

  /// Call when the operation ends, whatever the outcome.
  public mutating func reset() {
    pendingText = nil
  }

  /// What to tell the user about `error`, and the text to keep, if any.
  /// A cancellation keeps nothing: the user asked for nothing to happen.
  public func outcome(for error: MicAIError) -> (message: String, keptText: String?) {
    guard let pendingText, !pendingText.isEmpty, error != .cancelled else {
      return (error.localizedDescription, nil)
    }
    return (error.localizedDescription + " " + Self.hint, pendingText)
  }
}
