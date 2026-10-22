import Foundation

/// What a custom mode produced, and where it should go.
public struct CustomModeResult: Sendable, Equatable {
  public let text: String
  public let output: CustomModeOutput
  /// For `.insert`: what to do in the target application.
  public let insertionIntent: InsertionIntent

  public init(text: String, output: CustomModeOutput, insertionIntent: InsertionIntent) {
    self.text = text
    self.output = output
    self.insertionIntent = insertionIntent
  }
}

/// Runs one custom mode: the user's instructions, what they said, and the
/// selection as data.
///
/// Like `TranslationEngine`, everything it needs is passed in, because it runs
/// off the main actor inside `CommandPipeline`.
public struct CustomModeEngine: Sendable {
  private let transformer: any LLMTransforming
  private let makeSessionID: @Sendable () -> UUID

  public init(
    transformer: any LLMTransforming,
    makeSessionID: @escaping @Sendable () -> UUID = UUID.init
  ) {
    self.transformer = transformer
    self.makeSessionID = makeSessionID
  }

  public func run(
    _ mode: CustomMode,
    spokenText: String,
    selectedText: String?,
    model: String
  ) async throws -> CustomModeResult {
    guard mode.isComplete else {
      throw MicAIError.llmIncomplete
    }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.llmServerFailure
    }
    let spoken = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasSelection = selectedText?.isEmpty == false
    // A mode can work on the selection alone ("bullet points" over selected
    // notes), but with neither speech nor a selection there is nothing to do.
    guard !spoken.isEmpty || hasSelection else {
      throw MicAIError.asrFailed
    }

    let output = try await transformer.transform(
      LLMRequest(
        instruction: Self.instruction(for: mode, spokenText: spoken),
        selectedText: hasSelection ? selectedText : nil,
        model: model,
        sessionID: makeSessionID(),
        kind: .custom
      )
    )
    let text = RefinementEngine.stripWrapping(output)
    guard !text.isEmpty else {
      throw MicAIError.llmIncomplete
    }

    let intent: InsertionIntent = hasSelection ? .replaceSelection(text) : .insert(text)
    return CustomModeResult(text: text, output: mode.output, insertionIntent: intent)
  }

  /// The mode's instructions and what was said, labelled so neither is
  /// mistaken for the other.
  public static func instruction(for mode: CustomMode, spokenText: String) -> String {
    let rules = mode.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    let said = spokenText.isEmpty ? "(nothing)" : spokenText
    return "Mode instructions: \(rules)\n\nWhat I said: \(said)"
  }
}
