import Foundation

public enum SelectionResult: Sendable, Equatable {
  case text(String)
  case noSelection

  init(snapshot: PasteboardSnapshot) {
    for item in snapshot.items {
      for type in Self.plainTextTypes {
        guard let data = item[type] else {
          continue
        }
        let encoding: String.Encoding = type.contains("utf16") ? .utf16 : .utf8
        if let text = String(data: data, encoding: encoding) {
          self = text.isEmpty ? .noSelection : .text(text)
          return
        }
      }
    }
    self = .noSelection
  }

  private static let plainTextTypes = [
    "public.utf8-plain-text",
    "public.utf16-plain-text",
    "public.plain-text",
    "NSStringPboardType",
  ]
}
