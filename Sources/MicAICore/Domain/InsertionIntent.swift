public enum InsertionIntent: Sendable, Equatable {
  case insert(String)
  case replaceSelection(String)

  public var text: String {
    switch self {
    case .insert(let text), .replaceSelection(let text):
      text
    }
  }
}
