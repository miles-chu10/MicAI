import Foundation
import MicAICore
import Testing

@Suite
struct TranslationEngineTests {
  @Test
  func selectionIsTranslatedAndReplacesIt() async throws {
    let transformer = RecordingTransformer(output: "Env\u{ed}alo el martes.")
    let engine = TranslationEngine(transformer: transformer)

    let intent = try await engine.translate(
      spokenText: "ignored because something is selected",
      selectedText: "Send it on Tuesday.",
      targetLanguage: "Spanish",
      model: "gpt-5-codex"
    )

    #expect(intent == .replaceSelection("Env\u{ed}alo el martes."))
    let request = try #require(await transformer.lastRequest)
    #expect(request.kind == .translation)
    #expect(request.selectedText == "Send it on Tuesday.")
    #expect(request.instruction == "Target language: Spanish.")
  }

  @Test
  func withoutASelectionTheSpeechIsTranslatedAndInserted() async throws {
    let transformer = RecordingTransformer(output: "Bis morgen.")
    let engine = TranslationEngine(transformer: transformer)

    let intent = try await engine.translate(
      spokenText: "see you tomorrow",
      selectedText: nil,
      targetLanguage: "German",
      model: "gpt-5-codex"
    )

    #expect(intent == .insert("Bis morgen."))
    #expect(await transformer.lastRequest?.selectedText == "see you tomorrow")
  }

  @Test
  func anEmptySelectionIsTreatedAsNoSelection() async throws {
    // readSelection can legitimately return "" for a focused-but-empty field.
    let transformer = RecordingTransformer(output: "Hola.")
    let engine = TranslationEngine(transformer: transformer)

    let intent = try await engine.translate(
      spokenText: "hello",
      selectedText: "",
      targetLanguage: "Spanish",
      model: "gpt-5-codex"
    )

    #expect(intent == .insert("Hola."))
  }

  @Test
  func missingLanguageFailsBeforeAnyRequest() async throws {
    let transformer = RecordingTransformer(output: "unused")
    let engine = TranslationEngine(transformer: transformer)

    await expectFailure(is: .translationLanguageMissing) {
      _ = try await engine.translate(
        spokenText: "hello",
        selectedText: nil,
        targetLanguage: "   ",
        model: "gpt-5-codex"
      )
    }
    #expect(await transformer.callCount == 0)
  }

  @Test
  func blankModelUsesTheProviderDefault() async throws {
    let transformer = RecordingTransformer(output: "hola")
    let engine = TranslationEngine(transformer: transformer)

    _ = try await engine.translate(
      spokenText: "hello",
      selectedText: nil,
      targetLanguage: "Spanish",
      model: " "
    )
    #expect(await transformer.callCount == 1)
  }

  @Test
  func nothingToTranslateFailsAsASRFailure() async throws {
    let transformer = RecordingTransformer(output: "unused")
    let engine = TranslationEngine(transformer: transformer)

    await expectFailure(is: .asrFailed) {
      _ = try await engine.translate(
        spokenText: "   ",
        selectedText: nil,
        targetLanguage: "Spanish",
        model: "gpt-5-codex"
      )
    }
  }

  @Test
  func emptyModelOutputFailsAsIncomplete() async throws {
    let transformer = RecordingTransformer(output: "   ")
    let engine = TranslationEngine(transformer: transformer)

    await expectFailure(is: .llmIncomplete) {
      _ = try await engine.translate(
        spokenText: "hello",
        selectedText: nil,
        targetLanguage: "Spanish",
        model: "gpt-5-codex"
      )
    }
  }

  @Test
  func fencedOutputIsUnwrapped() async throws {
    let transformer = RecordingTransformer(output: "```\nBonjour.\n```")
    let engine = TranslationEngine(transformer: transformer)

    let intent = try await engine.translate(
      spokenText: "hello",
      selectedText: nil,
      targetLanguage: "French",
      model: "gpt-5-codex"
    )

    #expect(intent == .insert("Bonjour."))
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

actor RecordingTransformer: LLMTransforming {
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
