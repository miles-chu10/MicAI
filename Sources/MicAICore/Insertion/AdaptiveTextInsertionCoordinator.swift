public actor AdaptiveTextInsertionCoordinator {
  private let directInserter: any DirectTextInserting
  private let clipboardFallback: TextInsertionCoordinator

  public init(
    directInserter: any DirectTextInserting,
    clipboardFallback: TextInsertionCoordinator
  ) {
    self.directInserter = directInserter
    self.clipboardFallback = clipboardFallback
  }

  public func apply(
    _ intent: InsertionIntent,
    to target: TargetIdentity,
    while operationIsCurrent: @escaping @Sendable () async -> Bool = { true }
  ) async throws {
    guard await operationIsCurrent() else {
      throw MicAIError.cancelled
    }

    switch intent {
    case .insert(let text), .replaceSelection(let text):
      if await directInserter.insert(text, into: target) {
        return
      }
    case .insertAfterSelection:
      // Direct insertion writes over the selection, which this intent must
      // keep; the keyboard path moves past it first.
      break
    }

    try await clipboardFallback.apply(
      intent,
      to: target,
      while: operationIsCurrent
    )
  }
}
