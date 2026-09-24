import Foundation
import MicAICore
import Testing

@Suite
struct DictationComposerTests {
  @Test
  func appliesVocabularyBeforeRefinementSoTheModelSeesTheCorrectSpelling() async throws {
    let harness = try await Harness()
    await harness.vocabulary.upsert(VocabularyEntry(heard: "paraquet", written: "Parakeet"))
    await harness.refiner.setOutput("We use Parakeet locally.")

    let result = await harness.composer.compose(
      transcript: transcript("we use paraquet locally"),
      mode: .dictation,
      target: harness.slackTarget,
      settings: harness.settings()
    )

    let seen = await harness.refiner.lastRequest
    #expect(seen?.transcript == "we use Parakeet locally")
    #expect(result.text == "We use Parakeet locally.")
    #expect(result.refined)
  }

  @Test
  func resolvesToneFromTheTargetApplication() async throws {
    let harness = try await Harness()
    await harness.refiner.setOutput("hey, shipping this today")

    let result = await harness.composer.compose(
      transcript: transcript("hey shipping this today"),
      mode: .dictation,
      target: harness.slackTarget,
      settings: harness.settings()
    )

    #expect(result.tone == .casual)
    #expect(await harness.refiner.lastRequest?.tone == .casual)
  }

  @Test
  func privacyModeKeepsEverythingLocal() async throws {
    let harness = try await Harness()
    await harness.vocabulary.upsert(VocabularyEntry(heard: "paraquet", written: "Parakeet"))
    var settings = harness.settings()
    settings.privacyMode = true

    let result = await harness.composer.compose(
      transcript: transcript("we use paraquet locally"),
      mode: .dictation,
      target: harness.slackTarget,
      settings: settings
    )

    // Vocabulary still applies — it never leaves the machine.
    #expect(result.text == "we use Parakeet locally")
    #expect(!result.refined)
    #expect(result.tone == nil)
    #expect(await harness.refiner.callCount == 0)
  }

  @Test
  func refinementFailureStillInsertsTheTranscript() async throws {
    let harness = try await Harness()
    await harness.refiner.setFailure(.llmRateLimited)

    let result = await harness.composer.compose(
      transcript: transcript("this must not be lost"),
      mode: .dictation,
      target: nil,
      settings: harness.settings()
    )

    #expect(result.text == "this must not be lost")
    #expect(!result.refined)
    #expect(result.refinementFailure == .llmRateLimited)
  }

  @Test
  func historyRecordsRawAndFinalTextWhenEnabled() async throws {
    let harness = try await Harness()
    await harness.refiner.setOutput("Shipping this today.")

    let result = await harness.composer.compose(
      transcript: transcript("uh shipping this today"),
      mode: .dictation,
      target: harness.slackTarget,
      settings: harness.settings()
    )

    let entries = await harness.history.all()
    #expect(entries.count == 1)
    #expect(entries.first?.rawTranscript == "uh shipping this today")
    #expect(entries.first?.finalText == "Shipping this today.")
    #expect(entries.first?.applicationName == "Slack")
    #expect(entries.first?.id == result.historyEntryID)
  }

  @Test
  func cancelledDictationIsNotRecorded() async throws {
    let harness = try await Harness()
    let composer = harness.composer
    let settings = harness.settings()
    let spoken = transcript("never mind")

    let result = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await composer.compose(
        transcript: spoken,
        mode: .dictation,
        target: nil,
        settings: settings
      )
    }.value

    #expect(await harness.history.all().isEmpty)
    #expect(result.historyEntryID == nil)
  }

  @Test
  func historyDisabledRecordsNothing() async throws {
    let harness = try await Harness()
    var settings = harness.settings()
    settings.historyEnabled = false

    let result = await harness.composer.compose(
      transcript: transcript("nothing to see"),
      mode: .dictation,
      target: nil,
      settings: settings
    )

    #expect(await harness.history.all().isEmpty)
    #expect(result.historyEntryID == nil)
  }

  @Test
  func correctingAHistoryEntryTeachesTheVocabulary() async throws {
    let harness = try await Harness()
    await harness.refiner.setOutput("We use paraquet locally.")

    let result = await harness.composer.compose(
      transcript: transcript("we use paraquet locally"),
      mode: .dictation,
      target: nil,
      settings: harness.settings()
    )
    let entryID = try #require(result.historyEntryID)

    let proposals = await harness.composer.applyCorrection(
      historyEntryID: entryID,
      correctedText: "we use Parakeet locally"
    )

    #expect(proposals.count == 1)
    let stored = await harness.vocabulary.all()
    #expect(stored.contains { $0.heard == "paraquet" && $0.written == "Parakeet" })
  }

  @Test
  func vocabularyHitCountsAreRecorded() async throws {
    let harness = try await Harness()
    await harness.vocabulary.upsert(VocabularyEntry(heard: "paraquet", written: "Parakeet"))
    var settings = harness.settings()
    settings.refinementEnabled = false

    _ = await harness.composer.compose(
      transcript: transcript("paraquet again"),
      mode: .dictation,
      target: nil,
      settings: settings
    )

    #expect(await harness.vocabulary.all().first?.hitCount == 1)
  }

  private func transcript(_ text: String) -> Transcript {
    Transcript(
      text: text,
      audioDuration: 2,
      processingDuration: 0.1,
      confidence: 0.9
    )
  }
}

/// Temp-directory-backed stores plus a scripted refiner.
private struct Harness {
  let directory: URL
  let vocabulary: VocabularyStore
  let history: TranscriptHistoryStore
  let refiner: ScriptedRefiner
  let composer: DictationComposer

  let slackTarget = TargetIdentity(
    processIdentifier: 1,
    bundleIdentifier: "com.tinyspeck.slackmacgap",
    applicationName: "Slack"
  )

  init() async throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MicAITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    vocabulary = VocabularyStore(file: directory.appendingPathComponent("vocabulary.json"))
    history = TranscriptHistoryStore(file: directory.appendingPathComponent("history.json"))
    refiner = ScriptedRefiner()
    composer = DictationComposer(
      refiner: refiner,
      vocabulary: vocabulary,
      history: history
    )

    await vocabulary.load()
    await history.load()
  }

  func settings() -> AppSettings {
    AppSettings(
      dictationHotkey: .rightOption,
      commandHotkey: nil,
      dictationActivationMode: .hold,
      llmModel: "gpt-5-codex"
    )
  }
}

private actor ScriptedRefiner: TranscriptRefining {
  private var output: String?
  private var failure: MicAIError?
  private(set) var lastRequest: RefinementRequest?
  private(set) var callCount = 0

  func setOutput(_ value: String) {
    output = value
    failure = nil
  }

  func setFailure(_ value: MicAIError) {
    failure = value
    output = nil
  }

  func refine(_ request: RefinementRequest) async -> RefinementOutcome {
    callCount += 1
    lastRequest = request

    if let failure {
      return RefinementOutcome(text: request.transcript, refined: false, failure: failure)
    }
    guard let output else {
      return RefinementOutcome(text: request.transcript, refined: false)
    }
    return RefinementOutcome(text: output, refined: true)
  }
}
