import Foundation
import MicAICore
import Testing

@Suite
struct CommandEngineTests {
  @Test
  func selectionPresentRoutesToReplacement() async throws {
    let transformer = FakeTransformer(output: "HELLO")
    let engine = CommandEngine(transformer: transformer)

    let intent = try await engine.execute(
      instruction: "make this uppercase",
      selectedText: "hello",
      model: "gpt-5-codex"
    )

    #expect(intent == .replaceSelection("HELLO"))
  }

  @Test
  func selectionAbsentRoutesToInsertion() async throws {
    let transformer = FakeTransformer(output: "A haiku")
    let engine = CommandEngine(transformer: transformer)

    let intent = try await engine.execute(
      instruction: "write a haiku",
      selectedText: nil,
      model: "gpt-5-codex"
    )

    #expect(intent == .insert("A haiku"))
  }

  @Test
  func forwardsInstructionSelectionModelAndSessionToTransformer() async throws {
    let sessionID = UUID()
    let transformer = FakeTransformer(output: "done")
    let engine = CommandEngine(transformer: transformer, makeSessionID: { sessionID })

    _ = try await engine.execute(
      instruction: "translate",
      selectedText: "bonjour",
      model: "gpt-5-codex"
    )

    let request = try #require(await transformer.lastRequest)
    #expect(request.instruction == "translate")
    #expect(request.selectedText == "bonjour")
    #expect(request.model == "gpt-5-codex")
    #expect(request.sessionID == sessionID)
  }

  @Test
  func blankInstructionFailsAsASRFailureWithoutCallingTransformer() async throws {
    let transformer = FakeTransformer(output: "ignored")
    let engine = CommandEngine(transformer: transformer)

    await expectFailure(is: .asrFailed) {
      try await engine.execute(instruction: "   ", selectedText: "hello", model: "gpt-5-codex")
    }
    #expect(await transformer.callCount == 0)
  }

  @Test
  func blankModelFailsAsServerFailure() async {
    let engine = CommandEngine(transformer: FakeTransformer(output: "ignored"))

    await expectFailure(is: .llmServerFailure) {
      try await engine.execute(instruction: "do it", selectedText: nil, model: "  ")
    }
  }

  @Test
  func emptyTransformerOutputFailsAsIncomplete() async {
    let engine = CommandEngine(transformer: FakeTransformer(output: "   "))

    await expectFailure(is: .llmIncomplete) {
      try await engine.execute(instruction: "do it", selectedText: nil, model: "gpt-5-codex")
    }
  }

  private func expectFailure(
    is expected: MicAIError,
    _ operation: () async throws -> InsertionIntent
  ) async {
    do {
      _ = try await operation()
      Issue.record("Expected \(expected)")
    } catch {
      #expect(error as? MicAIError == expected)
    }
  }
}

private actor FakeTransformer: LLMTransforming {
  private let output: String
  private(set) var lastRequest: LLMRequest?
  private(set) var callCount = 0

  init(output: String) {
    self.output = output
  }

  func transform(_ request: LLMRequest) async throws -> String {
    callCount += 1
    lastRequest = request
    return output
  }
}
