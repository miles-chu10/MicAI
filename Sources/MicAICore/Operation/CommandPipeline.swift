import Foundation

public struct CommandResult: Sendable, Equatable {
  public let instruction: Transcript
  public let sourceText: String?
  public let intent: InsertionIntent

  public init(
    instruction: Transcript,
    sourceText: String? = nil,
    intent: InsertionIntent
  ) {
    self.instruction = instruction
    self.sourceText = sourceText
    self.intent = intent
  }
}

public actor CommandPipeline {
  private struct Context: Sendable {
    let selectedText: String?
  }

  private let dictationPipeline: DictationPipeline
  private let commandEngine: any CommandExecuting
  private let insertionCoordinator: TextInsertionCoordinator
  private let coordinator: OperationCoordinator
  private var contexts: [UUID: Context] = [:]

  public init(
    dictationPipeline: DictationPipeline,
    commandEngine: any CommandExecuting,
    insertionCoordinator: TextInsertionCoordinator,
    coordinator: OperationCoordinator
  ) {
    self.dictationPipeline = dictationPipeline
    self.commandEngine = commandEngine
    self.insertionCoordinator = insertionCoordinator
    self.coordinator = coordinator
  }

  public func begin(
    target: TargetIdentity,
    levels: @escaping @Sendable (Float) -> Void,
    maximumDurationReached: @escaping @Sendable () -> Void = {},
    operationStarted: @escaping @Sendable (UUID) async -> Void = { _ in }
  ) async throws -> UUID {
    let operationID = try await dictationPipeline.begin(
      mode: .command,
      target: target,
      levels: levels,
      maximumDurationReached: maximumDurationReached,
      operationStarted: operationStarted
    )

    do {
      let selectedText = try await insertionCoordinator.readSelection(from: target)
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      contexts[operationID] = Context(selectedText: selectedText)
      return operationID
    } catch {
      await dictationPipeline.cancel(operationID: operationID)
      throw (error as? MicAIError) ?? MicAIError.insertionFailed
    }
  }

  public func finish(
    operationID: UUID,
    model: String,
    awaitingLLM: @escaping @Sendable () async -> Void = {}
  ) async throws -> CommandResult {
    guard let context = contexts.removeValue(forKey: operationID) else {
      throw MicAIError.invalidTransition
    }

    let instruction = try await dictationPipeline.finish(operationID: operationID)
    guard await coordinator.markAwaitingLLM(operationID: operationID) else {
      throw MicAIError.cancelled
    }
    await awaitingLLM()

    let commandEngine = self.commandEngine
    let task = Task<InsertionIntent, Error> {
      try Task.checkCancellation()
      return try await commandEngine.execute(
        instruction: instruction.text,
        selectedText: context.selectedText,
        model: model,
        requestID: operationID
      )
    }
    guard
      await coordinator.registerCancellationHandler(
        { task.cancel() },
        operationID: operationID
      )
    else {
      throw MicAIError.cancelled
    }

    do {
      let intent = try await task.value
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      return CommandResult(
        instruction: instruction,
        sourceText: context.selectedText,
        intent: intent
      )
    } catch let error as MicAIError {
      if await coordinator.isCurrent(operationID: operationID) {
        _ = await coordinator.fail(operationID: operationID, error: error)
      }
      throw error
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch {
      if await coordinator.isCurrent(operationID: operationID) {
        _ = await coordinator.fail(
          operationID: operationID,
          error: .llmServerFailure
        )
      }
      throw MicAIError.llmServerFailure
    }
  }

  public func cancel(operationID: UUID) async {
    contexts.removeValue(forKey: operationID)
    await dictationPipeline.cancel(operationID: operationID)
  }
}
