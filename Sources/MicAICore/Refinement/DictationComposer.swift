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

  public init(
    text: String,
    tone: StyleTone?,
    refined: Bool,
    refinementFailure: MicAIError? = nil,
    historyEntryID: UUID? = nil
  ) {
    self.text = text
    self.tone = tone
    self.refined = refined
    self.refinementFailure = refinementFailure
    self.historyEntryID = historyEntryID
  }
}

/// The post-transcription stage: vocabulary, tone, refinement, history.
///
/// `DictationPipeline` stops at a clean transcript. Everything that turns that
/// transcript into the text a user actually wants lives here, in one place, so
/// the ordering guarantees hold no matter which UI calls it:
///
/// 1. vocabulary substitution runs first, locally, so proper nouns are right
///    even when refinement is off or offline,
/// 2. refinement runs second and sees the corrected spelling,
/// 3. history records both the raw transcript and the final text, so a later
///    correction can be diffed against what the recognizer actually heard.
public actor DictationComposer {
  private let refiner: any TranscriptRefining
  private let vocabulary: VocabularyStore
  private let history: TranscriptHistoryStore
  private let applier: VocabularyApplier

  public init(
    refiner: any TranscriptRefining,
    vocabulary: VocabularyStore,
    history: TranscriptHistoryStore,
    applier: VocabularyApplier = VocabularyApplier()
  ) {
    self.refiner = refiner
    self.vocabulary = vocabulary
    self.history = history
    self.applier = applier
  }

  public func compose(
    transcript: Transcript,
    mode: MicAIMode,
    target: TargetIdentity?,
    settings: AppSettings
  ) async -> ComposedDictation {
    let rawText = transcript.text

    let entries = await vocabulary.all()
    let substitution = applier.apply(rawText, entries: entries)
    if !substitution.appliedEntryIDs.isEmpty {
      await vocabulary.recordHits(entryIDs: substitution.appliedEntryIDs)
    }

    var text = substitution.text
    var tone: StyleTone?
    var refined = false
    var failure: MicAIError?

    if settings.isRefinementActive {
      let resolvedTone = settings.resolver().tone(for: target)
      let outcome = await refiner.refine(
        RefinementRequest(
          transcript: text,
          tone: resolvedTone,
          vocabularyContext: applier.promptContext(entries: entries),
          model: settings.llmModel
        )
      )
      text = outcome.text
      tone = resolvedTone
      refined = outcome.refined
      failure = outcome.failure
    }

    var historyEntryID: UUID?
    if settings.historyEnabled {
      let entry = HistoryEntry(
        mode: mode,
        rawTranscript: rawText,
        finalText: text,
        applicationName: target?.applicationName,
        bundleIdentifier: target?.bundleIdentifier,
        tone: tone,
        audioDuration: transcript.audioDuration,
        refined: refined
      )
      await history.record(entry)
      historyEntryID = entry.id
    }

    return ComposedDictation(
      text: text,
      tone: tone,
      refined: refined,
      refinementFailure: failure,
      historyEntryID: historyEntryID
    )
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
