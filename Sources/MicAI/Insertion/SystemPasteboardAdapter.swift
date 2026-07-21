import AppKit
import Foundation
import MicAICore

final class SystemPasteboardAdapter: PasteboardAccessing, @unchecked Sendable {
  private let pasteboard: NSPasteboard
  private let lock = NSLock()

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func snapshot() throws -> PasteboardSnapshot {
    try locked {
      for _ in 0..<2 {
        let initialChangeCount = pasteboard.changeCount
        let items: [[String: Data]] =
          pasteboard.pasteboardItems?.map { item in
            var representations: [String: Data] = [:]
            for type in item.types {
              if let data = item.data(forType: type) {
                representations[type.rawValue] = data
              }
            }
            return representations
          } ?? []
        let finalChangeCount = pasteboard.changeCount
        if initialChangeCount == finalChangeCount {
          return PasteboardSnapshot(items: items, changeCount: finalChangeCount)
        }
      }
      throw MicAIError.clipboardChanged
    }
  }

  func writePlainText(_ text: String) throws -> Int {
    try locked {
      pasteboard.clearContents()
      guard pasteboard.setString(text, forType: .string) else {
        throw MicAIError.insertionFailed
      }
      return pasteboard.changeCount
    }
  }

  func restore(_ snapshot: PasteboardSnapshot) throws {
    try locked {
      pasteboard.clearContents()
      guard !snapshot.items.isEmpty else {
        return
      }

      let items = try snapshot.items.map { representations in
        let item = NSPasteboardItem()
        for (typeName, data) in representations {
          guard item.setData(data, forType: .init(typeName)) else {
            throw MicAIError.insertionFailed
          }
        }
        return item
      }
      guard pasteboard.writeObjects(items) else {
        throw MicAIError.insertionFailed
      }
    }
  }

  func currentChangeCount() -> Int {
    locked { pasteboard.changeCount }
  }

  private func locked<T>(_ operation: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}
