import Foundation

public struct CommandResult: Sendable, Equatable {
  public let instruction: Transcript
  public let intent: InsertionIntent

  public init(instruction: Transcript, intent: InsertionIntent) {
    self.instruction = instruction
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

  /// `mode` distinguishes AI Commands, AI Translate and Ask AI. All three need
  /// exactly this preamble -- record audio, then read the selection before the
  /// user's focus can move -- so they share the pipeline and differ only in the
  /// closure passed to `finish`.
  public func begin(
    mode: MicAIMode = .command,
    target: TargetIdentity,
    levels: @escaping @Sendable (Float) -> Void,
    operationStarted: @escaping @Sendable (UUID) async -> Void = { _ in },
    partials: (@Sendable (String) -> Void)? = nil
  ) async throws -> UUID {
    let operationID = try await dictationPipeline.begin(
      mode: mode,
      target: target,
      levels: levels,
      operationStarted: operationStarted,
      partials: partials
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
    let commandEngine = self.commandEngine
    let produced = try await finish(
      operationID: operationID,
      awaitingLLM: awaitingLLM
    ) { spokenText, selectedText in
      try await commandEngine.execute(
        instruction: spokenText,
        selectedText: selectedText,
        model: model
      )
    }
    return CommandResult(instruction: produced.instruction, intent: produced.value)
  }

  /// Runs the transcript and captured selection through `produce`, under the
  /// same cancellation and error mapping as an AI Command.
  ///
  /// Generic in the result so Ask AI can return an answer plus its destination
  /// rather than an `InsertionIntent` -- an answer does not always go to the
  /// cursor, and forcing it through the insertion type would have hidden that.
  public func finish<Value: Sendable>(
    operationID: UUID,
    awaitingLLM: @escaping @Sendable () async -> Void = {},
    produce: @escaping @Sendable (String, String?) async throws -> Value
  ) async throws -> (instruction: Transcript, value: Value) {
    guard let context = contexts.removeValue(forKey: operationID) else {
      throw MicAIError.invalidTransition
    }

    let instruction = try await dictationPipeline.finish(operationID: operationID)
    guard await coordinator.markAwaitingLLM(operationID: operationID) else {
      throw MicAIError.cancelled
    }
    await awaitingLLM()

    let spokenText = instruction.text
    let selectedText = context.selectedText
    let task = Task<Value, Error> {
      try Task.checkCancellation()
      return try await produce(spokenText, selectedText)
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
      let value = try await task.value
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      return (instruction, value)
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
