public enum InsertionIntent: Sendable, Equatable {
  case insert(String)
  case replaceSelection(String)
}
