import Foundation

public protocol CommandExecuting: Sendable {
  func execute(
    instruction: String,
    selectedText: String?,
    model: String
  ) async throws -> InsertionIntent
}

public struct CommandEngine: CommandExecuting, Sendable {
  private let transformer: any LLMTransforming
  private let makeSessionID: @Sendable () -> UUID

  public init(
    transformer: any LLMTransforming,
    makeSessionID: @escaping @Sendable () -> UUID = UUID.init
  ) {
    self.transformer = transformer
    self.makeSessionID = makeSessionID
  }

  public func execute(
    instruction: String,
    selectedText: String?,
    model: String
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
        sessionID: makeSessionID()
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
