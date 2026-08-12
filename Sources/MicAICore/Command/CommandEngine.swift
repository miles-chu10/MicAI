import Foundation

public protocol CommandExecuting: Sendable {
  func execute(
    instruction: String,
    selectedText: String?,
    model: String
  ) async throws -> InsertionIntent

  func execute(
    instruction: String,
    selectedText: String?,
    model: String,
    requestID: UUID
  ) async throws -> InsertionIntent
}

extension CommandExecuting {
  public func execute(
    instruction: String,
    selectedText: String?,
    model: String,
    requestID: UUID
  ) async throws -> InsertionIntent {
    try await execute(
      instruction: instruction,
      selectedText: selectedText,
      model: model
    )
  }
}

public struct CommandEngine: CommandExecuting, Sendable {
  private let transformer: any LLMTransforming
  private let makeSessionID: @Sendable () -> UUID

  public init(
    transformer: any LLMTransforming,
    makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.transformer = transformer
    self.makeSessionID = makeSessionID
  }

  public func execute(
    instruction: String,
    selectedText: String?,
    model: String
  ) async throws -> InsertionIntent {
    try await execute(
      instruction: instruction,
      selectedText: selectedText,
      model: model,
      requestID: makeSessionID()
    )
  }

  public func execute(
    instruction: String,
    selectedText: String?,
    model: String,
    requestID: UUID
  ) async throws -> InsertionIntent {
    guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.asrFailed
    }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.llmServerFailure
    }

    let output = try await transformer.transform(
      LLMRequest(
        instruction: instruction,
        selectedText: selectedText,
        model: model,
        sessionID: requestID
      )
    )
    guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.llmIncomplete
    }

    if selectedText == nil {
      return .insert(output)
    }
    return .replaceSelection(output)
  }
}
