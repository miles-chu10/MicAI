import Foundation
import MicAICore
import Testing

@Suite
struct RefinementEngineTests {
  @Test
  func returnsRefinedTextOnSuccess() async {
    let engine = RefinementEngine(transformer: StubTransformer(result: .success("Ship it today.")))

    let outcome = await engine.refine(request(transcript: "um ship it uh today"))

    #expect(outcome.text == "Ship it today.")
    #expect(outcome.refined)
    #expect(outcome.failure == nil)
  }

  @Test
  func sendsToneGuidanceAndVocabularyAsTheInstruction() async {
    let transformer = StubTransformer(result: .success("ok"))
    let engine = RefinementEngine(transformer: transformer)

    _ = await engine.refine(
      RefinementRequest(
        transcript: "hey",
        tone: .technical,
        vocabularyContext: "Known corrections: \"paraquet\" -> \"Parakeet\".",
        model: "gpt-5-codex"
      )
    )

    let sent = await transformer.lastRequest
    #expect(sent?.kind == .refinement)
    #expect(sent?.selectedText == "hey")
    #expect(sent?.instruction.contains("Target register: technical") == true)
    #expect(sent?.instruction.contains("paraquet") == true)
  }

  @Test
  func fallsBackToTheTranscriptWhenTheModelThrows() async {
    let engine = RefinementEngine(
      transformer: StubTransformer(result: .failure(MicAIError.llmUnauthorized))
    )

    let outcome = await engine.refine(request(transcript: "keep this text"))

    #expect(outcome.text == "keep this text")
    #expect(!outcome.refined)
    #expect(outcome.failure == .llmUnauthorized)
  }

  @Test
  func fallsBackWhenTheModelReturnsNothingUsable() async {
    let engine = RefinementEngine(transformer: StubTransformer(result: .success("   ")))

    let outcome = await engine.refine(request(transcript: "keep this text"))

    #expect(outcome.text == "keep this text")
    #expect(outcome.failure == .llmIncomplete)
  }

  @Test
  func fallsBackWhenTheModelAnsweredInsteadOfRewriting() async {
    // A transcript ending in a question invites the model to reply to it.
    // Growth well past the input length is the tell.
    let transcript = String(repeating: "what is the capital of France ", count: 6)
    let essay = String(repeating: "Paris is the capital and largest city of France. ", count: 40)
    let engine = RefinementEngine(transformer: StubTransformer(result: .success(essay)))

    let outcome = await engine.refine(request(transcript: transcript))

    #expect(outcome.text == transcript)
    #expect(!outcome.refined)
    #expect(outcome.failure == .llmIncomplete)
  }

  @Test
  func shortTranscriptsAreNotRejectedForGrowth() async {
    let engine = RefinementEngine(transformer: StubTransformer(result: .success("Okay.")))

    let outcome = await engine.refine(request(transcript: "ok"))

    #expect(outcome.text == "Okay.")
    #expect(outcome.refined)
  }

  @Test
  func blankModelStillRefinesWithTheProviderDefault() async {
    let transformer = StubTransformer(result: .success("Hello there."))
    let engine = RefinementEngine(transformer: transformer)

    let outcome = await engine.refine(
      RefinementRequest(transcript: "hello there", tone: .neutral, model: "  ")
    )

    #expect(await transformer.callCount == 1)
  }

  @Test
  func blankTranscriptIsReturnedUntouchedWithoutCallingTheModel() async {
    let transformer = StubTransformer(result: .success("nope"))
    let engine = RefinementEngine(transformer: transformer)

    let outcome = await engine.refine(request(transcript: "   "))

    #expect(outcome.text == "   ")
    #expect(!outcome.refined)
    #expect(outcome.failure == nil)
    #expect(await transformer.callCount == 0)
  }

  @Test
  func stripsFencedCodeBlocksAndFullyWrappingQuotes() {
    #expect(RefinementEngine.stripWrapping("```\nShip it.\n```") == "Ship it.")
    #expect(RefinementEngine.stripWrapping("```text\nShip it.\n```") == "Ship it.")
    #expect(RefinementEngine.stripWrapping("\"Ship it.\"") == "Ship it.")
  }

  @Test
  func keepsQuotesThatArePartOfTheContent() {
    // Stripping here would silently drop quotation the speaker dictated.
    let quoted = "\"Ship it,\" she said, \"today.\""

    #expect(RefinementEngine.stripWrapping(quoted) == quoted)
  }

  private func request(transcript: String) -> RefinementRequest {
    RefinementRequest(transcript: transcript, tone: .neutral, model: "gpt-5-codex")
  }
}

private actor StubTransformer: LLMTransforming {
  private let result: Result<String, Error>
  private(set) var lastRequest: LLMRequest?
  private(set) var callCount = 0

  init(result: Result<String, Error>) {
    self.result = result
  }

  func transform(_ request: LLMRequest) async throws -> String {
    callCount += 1
    lastRequest = request
    return try result.get()
  }
}
