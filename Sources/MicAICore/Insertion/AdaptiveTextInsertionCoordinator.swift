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

    let text: String
    switch intent {
    case .insert(let value), .replaceSelection(let value):
      text = value
    }

    if await directInserter.insert(text, into: target) {
      return
    }

    try await clipboardFallback.apply(
      intent,
      to: target,
      while: operationIsCurrent
    )
  }
}
