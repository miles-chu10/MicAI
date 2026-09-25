import Foundation

public struct ComposedDictation: Sendable, Equatable {
  /// The text to insert. Never empty when the transcript was not empty.
  public let text: String
  /// The tone that was applied, or nil when refinement did not run.
  public let tone: StyleTone?
  public let refined: Bool
  /// Set when refinement was attempted and failed. The text is still usable —
  /// this exists so the HUD can explain why it reads rougher than usual.
  public let refinementFailure: MicAIError?
  public let historyEntryID: UUID?
  /// Set when the whole utterance was a snippet trigger and `text` is the
  /// snippet's expansion.
  public let snippetID: UUID?

  public init(
    text: String,
    tone: StyleTone?,
    refined: Bool,
    refinementFailure: MicAIError? = nil,
    historyEntryID: UUID? = nil,
    snippetID: UUID? = nil
  ) {
    self.text = text
    self.tone = tone
    self.refined = refined
    self.refinementFailure = refinementFailure
    self.historyEntryID = historyEntryID
    self.snippetID = snippetID
  }
}

/// The post-transcription stage: snippets, vocabulary, tone, refinement,
/// history.
///
/// `DictationPipeline` stops at a clean transcript. Everything that turns that
/// transcript into the text a user actually wants lives here, in one place, so
/// the ordering guarantees hold no matter which UI calls it:
///
/// 0. a snippet trigger short-circuits everything: the saved text goes in
///    verbatim, never through the model,
/// 1. vocabulary substitution runs first, locally, so proper nouns are right
///    even when refinement is off or offline,
/// 2. refinement runs second and sees the corrected spelling,
/// 3. history records both the raw transcript and the final text, so a later
///    correction can be diffed against what the recognizer actually heard.
public actor DictationComposer {
  private let refiner: any TranscriptRefining
  private let vocabulary: VocabularyStore
  private let history: TranscriptHistoryStore
  private let snippets: SnippetStore?
  private let onDeviceRefiner: (any TranscriptRefining)?
  private let applier: VocabularyApplier

  /// `onDeviceRefiner` is nil when this build or this Mac cannot run Apple's
  /// on-device model. Choosing on-device clean-up then inserts the transcript
  /// as recognised and says why, rather than quietly sending it to the network
  /// model the user chose not to use.
  public init(
    refiner: any TranscriptRefining,
    vocabulary: VocabularyStore,
    history: TranscriptHistoryStore,
    snippets: SnippetStore? = nil,
    onDeviceRefiner: (any TranscriptRefining)? = nil,
    applier: VocabularyApplier = VocabularyApplier()
  ) {
    self.refiner = refiner
    self.onDeviceRefiner = onDeviceRefiner
    self.vocabulary = vocabulary
    self.history = history
    self.snippets = snippets
    self.applier = applier
  }

  public func compose(
    transcript: Transcript,
    mode: MicAIMode,
    target: TargetIdentity?,
    settings: AppSettings
  ) async -> ComposedDictation {
    let rawText = transcript.text

    if mode == .dictation, let snippets,
      let snippet = SnippetMatcher.match(rawText, in: await snippets.all())
    {
      await snippets.recordUse(snippetID: snippet.id)
      let historyEntryID = await recordHistory(
        mode: mode,
        rawText: rawText,
        finalText: snippet.text,
        target: target,
        tone: nil,
        transcript: transcript,
        refined: false,
        settings: settings
      )
      return ComposedDictation(
        text: snippet.text,
        tone: nil,
        refined: false,
        historyEntryID: historyEntryID,
        snippetID: snippet.id
      )
    }

    let entries = await vocabulary.all()
    let substitution = applier.apply(rawText, entries: entries)
    if !substitution.appliedEntryIDs.isEmpty {
      await vocabulary.recordHits(entryIDs: substitution.appliedEntryIDs)
    }

    var text = substitution.text
    var tone: StyleTone?
    var refined = false
    var failure: MicAIError?

    if let route = settings.refinementRoute {
      let chosen: (any TranscriptRefining)? =
        route == .onDevice ? onDeviceRefiner : refiner
      if let chosen {
        let resolvedTone = settings.resolver().tone(for: target)
        let outcome = await chosen.refine(
          RefinementRequest(
            transcript: text,
            tone: resolvedTone,
            vocabularyContext: applier.promptContext(entries: entries),
            customInstructions: settings.customInstructions,
            model: route == .onDevice ? OnDeviceLanguageModel.modelName : settings.llmModel
          )
        )
        text = outcome.text
        tone = resolvedTone
        refined = outcome.refined
        failure = outcome.failure
      } else {
        failure = .onDeviceModelUnavailable
      }
    }

    let historyEntryID = await recordHistory(
      mode: mode,
      rawText: rawText,
      finalText: text,
      target: target,
      tone: tone,
      transcript: transcript,
      refined: refined,
      settings: settings
    )

    return ComposedDictation(
      text: text,
      tone: tone,
      refined: refined,
      refinementFailure: failure,
      historyEntryID: historyEntryID
    )
  }

  private func recordHistory(
    mode: MicAIMode,
    rawText: String,
    finalText: String,
    target: TargetIdentity?,
    tone: StyleTone?,
    transcript: Transcript,
    refined: Bool,
    settings: AppSettings
  ) async -> UUID? {
    guard settings.historyEnabled else {
      return nil
    }
    let entry = HistoryEntry(
      mode: mode,
      rawTranscript: rawText,
      finalText: finalText,
      applicationName: target?.applicationName,
      bundleIdentifier: target?.bundleIdentifier,
      tone: tone,
      audioDuration: transcript.audioDuration,
      refined: refined
    )
    await history.record(entry)
    return entry.id
  }

  /// Applies a correction the user typed in the history list and persists any
  /// vocabulary it implies, so the same word is right next time.
  @discardableResult
  public func applyCorrection(
    historyEntryID: UUID,
    correctedText: String
  ) async -> [VocabularyEntry] {
    let proposals = await history.correct(
      entryID: historyEntryID,
      to: correctedText
    )
    for proposal in proposals {
      await vocabulary.upsert(proposal)
    }
    return proposals
  }
}
