import Foundation
import MicAICore
import Testing

@Suite
struct AskIntentClassifierTests {
  private let classifier = AskIntentClassifier()

  @Test
  func aQuestionMarkRoutesToTheWindow() {
    #expect(classifier.destination(for: "when is the deploy?") == .answerWindow)
  }

  @Test
  func aLeadingInterrogativeRoutesToTheWindowWithoutPunctuation() {
    // Parakeet does not reliably emit question marks, so this is the test that
    // carries most real traffic.
    #expect(classifier.destination(for: "what does this regex do") == .answerWindow)
    #expect(classifier.destination(for: "How do I revert a merge") == .answerWindow)
    #expect(classifier.destination(for: "explain this stack trace") == .answerWindow)
  }

  @Test
  func contractionsAreRecognized() {
    #expect(classifier.destination(for: "what's the timezone there") == .answerWindow)
  }

  @Test
  func contentToWriteIsInsertedAtTheCursor() {
    #expect(
      classifier.destination(for: "draft a reply agreeing to Tuesday")
        == .insertAtCursor
    )
    #expect(classifier.destination(for: "thanks, that works for me") == .insertAtCursor)
  }

  @Test
  func anInterrogativeMidSentenceIsNotAQuestion() {
    // "send them what we agreed" is an instruction; only the first word counts.
    #expect(classifier.destination(for: "send them what we agreed") == .insertAtCursor)
  }

  @Test
  func emptyInputPrefersTheWindow() {
    // Nothing recognizable should never be pasted into the user's document.
    #expect(classifier.destination(for: "  ") == .answerWindow)
  }
}

@Suite
struct AskEngineTests {
  @Test
  func aQuestionIsAnsweredIntoTheWindow() async throws {
    let transformer = RecordingTransformer(output: "It runs at 09:00 UTC.")
    let engine = AskEngine(transformer: transformer)

    let result = try await engine.ask(
      question: "when does the nightly job run",
      selectedText: nil,
      model: "gpt-5-codex"
    )

    #expect(result.destination == .answerWindow)
    #expect(result.answer == "It runs at 09:00 UTC.")
    #expect(!result.usedSelection)
    #expect(await transformer.lastRequest?.kind == .ask)
  }

  @Test
  func contentIsInsertedAtTheCursor() async throws {
    let engine = AskEngine(transformer: RecordingTransformer(output: "Tuesday works."))

    let result = try await engine.ask(
      question: "draft a reply agreeing to Tuesday",
      selectedText: nil,
      model: "gpt-5-codex"
    )

    #expect(result.destination == .insertAtCursor)
    #expect(result.insertionIntent == .insert("Tuesday works."))
  }

  @Test
  func theSelectionIsSentAsContextAndNeverReplaced() async throws {
    let transformer = RecordingTransformer(output: "It matches a word boundary.")
    let engine = AskEngine(transformer: transformer)

    let result = try await engine.ask(
      question: "what does this do",
      selectedText: "\\\\bslack\\\\b",
      model: "gpt-5-codex"
    )

    #expect(result.usedSelection)
    #expect(await transformer.lastRequest?.selectedText == "\\\\bslack\\\\b")
    // Crucially not .replaceSelection: asking about a regex must not overwrite it.
    #expect(result.insertionIntent == .insert("It matches a word boundary."))
  }

  @Test
  func thePreferenceOnlyEverForcesTheWindow() async throws {
    let engine = AskEngine(transformer: RecordingTransformer(output: "Tuesday works."))

    let forced = try await engine.ask(
      question: "draft a reply agreeing to Tuesday",
      selectedText: nil,
      model: "gpt-5-codex",
      alwaysOpensWindow: true
    )

    #expect(forced.destination == .answerWindow)
  }

  @Test
  func blankQuestionFailsBeforeAnyRequest() async throws {
    let transformer = RecordingTransformer(output: "unused")
    let engine = AskEngine(transformer: transformer)

    await expectFailure(is: .asrFailed) {
      _ = try await engine.ask(question: "  ", selectedText: nil, model: "gpt-5-codex")
    }
    #expect(await transformer.callCount == 0)
  }

  @Test
  func emptyAnswerFailsAsIncomplete() async throws {
    let engine = AskEngine(transformer: RecordingTransformer(output: ""))

    await expectFailure(is: .llmIncomplete) {
      _ = try await engine.ask(
        question: "what time is it there",
        selectedText: nil,
        model: "gpt-5-codex"
      )
    }
  }

  @Test
  func anEmptySelectionIsNotTreatedAsContext() async throws {
    let transformer = RecordingTransformer(output: "Sure.")
    let engine = AskEngine(transformer: transformer)

    let result = try await engine.ask(
      question: "is that ok",
      selectedText: "",
      model: "gpt-5-codex"
    )

    #expect(!result.usedSelection)
    #expect(await transformer.lastRequest?.selectedText == nil)
  }

  // Matches the do/catch idiom used elsewhere in this suite rather than
  // #expect(throws:), so every error assertion in the package reads the same.
  private func expectFailure(
    is expected: MicAIError,
    _ operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      Issue.record("Expected \(expected)")
    } catch {
      #expect(error as? MicAIError == expected)
    }
  }
}
