public enum InsertionIntent: Sendable, Equatable {
  case insert(String)
  case replaceSelection(String)
  /// Types after the selection and leaves the selected text in place. For
  /// output that used the selection as context rather than rewriting it: a
  /// plain paste would overwrite text the user only asked about.
  case insertAfterSelection(String)

  /// The text this intent will put into the target, regardless of whether it
  /// lands at the cursor or over a selection.
  public var text: String {
    switch self {
    case .insert(let text), .replaceSelection(let text), .insertAfterSelection(let text):
      text
    }
  }
}
