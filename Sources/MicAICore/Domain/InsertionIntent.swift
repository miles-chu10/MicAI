public enum InsertionIntent: Sendable, Equatable {
  case insert(String)
  case replaceSelection(String)

  /// The text this intent will put into the target, regardless of whether it
  /// lands at the cursor or over a selection.
  public var text: String {
    switch self {
    case .insert(let text), .replaceSelection(let text):
      text
    }
  }
}
