import Foundation

public struct PasteboardSnapshot: Sendable, Equatable {
  public let items: [[String: Data]]
  public let changeCount: Int

  public init(items: [[String: Data]], changeCount: Int) {
    self.items = items
    self.changeCount = changeCount
  }
}

public protocol PasteboardAccessing: Sendable {
  func snapshot() throws -> PasteboardSnapshot
  func writePlainText(_ text: String) throws -> Int
  func restore(_ snapshot: PasteboardSnapshot) throws
  func currentChangeCount() -> Int
}

public protocol KeyboardSynthesizing: Sendable {
  func copy() throws
  func paste() throws
}

public protocol TargetValidating: Sendable {
  func isCurrent(_ target: TargetIdentity) async -> Bool
}
