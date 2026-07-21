import Foundation

public struct OperationSnapshot: Sendable, Equatable {
  public let operationID: UUID?
  public let mode: MicAIMode?
  public let target: TargetIdentity?
  public let phase: OperationPhase

  public init(
    operationID: UUID?,
    mode: MicAIMode?,
    target: TargetIdentity?,
    phase: OperationPhase
  ) {
    self.operationID = operationID
    self.mode = mode
    self.target = target
    self.phase = phase
  }
}

public actor OperationCoordinator {
  private struct ActiveOperation {
    let id: UUID
    let mode: MicAIMode
    let target: TargetIdentity
    var cancellationHandlers: [@Sendable () -> Void]
  }

  private var activeOperation: ActiveOperation?
  private var currentPhase: OperationPhase = .idle

  public init() {}

  public func begin(mode: MicAIMode, target: TargetIdentity) throws -> UUID {
    guard activeOperation == nil else {
      throw MicAIError.operationAlreadyActive
    }

    let operation = ActiveOperation(
      id: UUID(),
      mode: mode,
      target: target,
      cancellationHandlers: []
    )
    activeOperation = operation
    currentPhase = .recording
    return operation.id
  }

  public func stopRecording(operationID: UUID) async {
    _ = transition(
      operationID: operationID,
      from: [.recording],
      to: .transcribing
    )
  }

  public func markAwaitingLLM(operationID: UUID) -> Bool {
    transition(
      operationID: operationID,
      from: [.transcribing],
      to: .awaitingLLM
    )
  }

  public func markInserting(operationID: UUID) -> Bool {
    transition(
      operationID: operationID,
      from: [.transcribing, .awaitingLLM],
      to: .inserting
    )
  }

  @discardableResult
  public func registerCancellationTask(
    _ task: Task<Void, Never>,
    operationID: UUID
  ) -> Bool {
    registerCancellationHandler(
      { task.cancel() },
      operationID: operationID
    )
  }

  @discardableResult
  public func registerCancellationHandler(
    _ handler: @escaping @Sendable () -> Void,
    operationID: UUID
  ) -> Bool {
    guard var operation = activeOperation, operation.id == operationID else {
      handler()
      return false
    }

    operation.cancellationHandlers.append(handler)
    activeOperation = operation
    return true
  }

  @discardableResult
  public func complete(operationID: UUID) -> Bool {
    guard matches(operationID), currentPhase == .inserting else {
      return false
    }

    activeOperation = nil
    currentPhase = .idle
    return true
  }

  @discardableResult
  public func fail(operationID: UUID, error: MicAIError) -> Bool {
    guard matches(operationID) else {
      return false
    }

    for handler in activeOperation?.cancellationHandlers ?? [] {
      handler()
    }
    activeOperation = nil
    currentPhase = .failed(error)
    return true
  }

  public func cancel(operationID: UUID) async {
    guard matches(operationID) else {
      return
    }

    for handler in activeOperation?.cancellationHandlers ?? [] {
      handler()
    }
    activeOperation = nil
    currentPhase = .idle
  }

  public func snapshot() -> OperationSnapshot {
    OperationSnapshot(
      operationID: activeOperation?.id,
      mode: activeOperation?.mode,
      target: activeOperation?.target,
      phase: currentPhase
    )
  }

  public func isCurrent(operationID: UUID) -> Bool {
    matches(operationID)
  }

  private func matches(_ operationID: UUID) -> Bool {
    activeOperation?.id == operationID
  }

  private func transition(
    operationID: UUID,
    from allowedPhases: [OperationPhase],
    to nextPhase: OperationPhase
  ) -> Bool {
    guard matches(operationID), allowedPhases.contains(currentPhase) else {
      return false
    }

    currentPhase = nextPhase
    return true
  }
}
