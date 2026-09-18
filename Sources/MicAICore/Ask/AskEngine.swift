import Foundation

public struct AskResult: Sendable, Equatable {
  /// What the user asked, as transcribed.
  public let question: String
  public let answer: String
  public let destination: AskDestination
  /// True when the selection was sent as context.
  public let usedSelection: Bool

  public init(
    question: String,
    answer: String,
    destination: AskDestination,
    usedSelection: Bool
  ) {
    self.question = question
    self.answer = answer
    self.destination = destination
    self.usedSelection = usedSelection
  }

  /// How the answer reaches the user when it is not going to a window.
  public var insertionIntent: InsertionIntent {
    .insert(answer)
  }
}

/// Answers a spoken question, using the selection as context when there is one.
///
/// Distinct from `CommandEngine` in what it does with the selection: a command
/// REWRITES the selection and replaces it, whereas Ask reads the selection and
/// leaves it alone. Asking "what does this regex do" should never overwrite the
/// regex.
public struct AskEngine: Sendable {
  private let transformer: any LLMTransforming
  private let classifier: AskIntentClassifier
  private let makeSessionID: @Sendable () -> UUID

  public init(
    transformer: any LLMTransforming,
    classifier: AskIntentClassifier = AskIntentClassifier(),
    makeSessionID: @escaping @Sendable () -> UUID = UUID.init
  ) {
    self.transformer = transformer
    self.classifier = classifier
    self.makeSessionID = makeSessionID
  }

  /// `alwaysOpensWindow` is passed in rather than read from settings here: this
  /// runs off the main actor, where main-actor-isolated settings are out of
  /// reach.
  public func ask(
    question: String,
    selectedText: String?,
    model: String,
    alwaysOpensWindow: Bool = false
  ) async throws -> AskResult {
    let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuestion.isEmpty else {
      throw MicAIError.asrFailed
    }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.llmServerFailure
    }

    let context = selectedText?.isEmpty == false ? selectedText : nil
    let output = try await transformer.transform(
      LLMRequest(
        instruction: trimmedQuestion,
        selectedText: context,
        model: model,
        sessionID: makeSessionID(),
        kind: .ask
      )
    )
    let answer = RefinementEngine.stripWrapping(output)
    guard !answer.isEmpty else {
      throw MicAIError.llmIncomplete
    }

    // The preference only ever forces the window. Nothing routes an answer to
    // the cursor against the classifier, because a wrong insertion overwrites
    // or pollutes what the user was writing, while a wrong window is a glance.
    let destination =
      alwaysOpensWindow
      ? AskDestination.answerWindow
      : classifier.destination(for: trimmedQuestion)

    return AskResult(
      question: trimmedQuestion,
      answer: answer,
      destination: destination,
      usedSelection: context != nil
    )
  }
}
