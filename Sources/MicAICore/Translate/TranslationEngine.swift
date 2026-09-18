import Foundation

/// Turns the selection -- or, with nothing selected, what you just said -- into
/// another language.
///
/// The target language is a parameter, not a closure over settings: this runs
/// off the main actor inside `CommandPipeline`, so reaching back into
/// main-actor-isolated settings from here would trap. The caller reads the
/// setting where it is safe to and passes the value in.
public struct TranslationEngine: Sendable {
  private let transformer: any LLMTransforming
  private let makeSessionID: @Sendable () -> UUID

  public init(
    transformer: any LLMTransforming,
    makeSessionID: @escaping @Sendable () -> UUID = UUID.init
  ) {
    self.transformer = transformer
    self.makeSessionID = makeSessionID
  }

  /// `spokenText` is what the user said; it is the content to translate only
  /// when nothing was selected.
  public func translate(
    spokenText: String,
    selectedText: String?,
    targetLanguage: String,
    model: String
  ) async throws -> InsertionIntent {
    let language = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !language.isEmpty else {
      throw MicAIError.translationLanguageMissing
    }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.llmServerFailure
    }

    // A selection is what the user pointed at, so it wins over the audio. With
    // no selection the utterance itself is the thing to translate.
    let replacesSelection = selectedText?.isEmpty == false
    let source = replacesSelection ? (selectedText ?? "") : spokenText
    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.asrFailed
    }

    let output = try await transformer.transform(
      LLMRequest(
        instruction: "Target language: \(language).",
        selectedText: source,
        model: model,
        sessionID: makeSessionID(),
        kind: .translation
      )
    )
    let translated = RefinementEngine.stripWrapping(output)
    guard !translated.isEmpty else {
      throw MicAIError.llmIncomplete
    }

    return replacesSelection ? .replaceSelection(translated) : .insert(translated)
  }
}
