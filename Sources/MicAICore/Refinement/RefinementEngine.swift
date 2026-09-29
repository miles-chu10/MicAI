import Foundation

public struct RefinementRequest: Sendable, Equatable {
  /// The transcript after deterministic cleanup and vocabulary substitution.
  public let transcript: String
  public let tone: StyleTone
  /// Learned corrections, rendered as prompt context. See `VocabularyApplier`.
  public let vocabularyContext: String?
  /// The user's own standing rules, from Settings > Style.
  public let customInstructions: String?
  public let model: String

  public init(
    transcript: String,
    tone: StyleTone,
    vocabularyContext: String? = nil,
    customInstructions: String? = nil,
    model: String
  ) {
    self.transcript = transcript
    self.tone = tone
    self.vocabularyContext = vocabularyContext
    self.customInstructions = customInstructions
    self.model = model
  }

  /// The instruction sent alongside the transcript.
  ///
  /// The user's rules come last and are labelled as theirs, so a rule such as
  /// "use British spelling" refines the tone guidance rather than being read as
  /// part of the transcript.
  public var composedInstruction: String {
    var parts = [tone.guidance]
    if let vocabularyContext, !vocabularyContext.isEmpty {
      parts.append(vocabularyContext)
    }
    let rules = customInstructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !rules.isEmpty {
      parts.append("The user also asks you to follow these rules: \(rules)")
    }
    return parts.joined(separator: " ")
  }
}

public struct RefinementOutcome: Sendable, Equatable {
  /// Always safe to insert: the refined text, or the original transcript.
  public let text: String
  public let refined: Bool
  /// Why refinement was skipped, for the HUD and history. Nil on success and
  /// when refinement was never attempted.
  public let failure: MicAIError?

  public init(text: String, refined: Bool, failure: MicAIError? = nil) {
    self.text = text
    self.refined = refined
    self.failure = failure
  }
}

public protocol TranscriptRefining: Sendable {
  func refine(_ request: RefinementRequest) async -> RefinementOutcome
}

/// Turns a raw transcript into polished text via the LLM.
///
/// The contract that matters: this never throws and never returns empty. A
/// dictation the user already spoke must reach the cursor even when the network
/// is down, the credential expired, or the model returned nonsense — degraded
/// text beats lost text, every time. Failures surface through
/// `RefinementOutcome.failure` so the UI can say so without blocking insertion.
public struct RefinementEngine: TranscriptRefining, Sendable {
  /// Output longer than this multiple of the input is treated as the model
  /// having answered the transcript rather than rewritten it.
  private static let maximumGrowthFactor = 3
  /// Below this length, the growth factor is too tight to be meaningful —
  /// "ok" legitimately becomes "Okay." and punctuation alone can double a
  /// very short transcript.
  private static let growthFloor = 120

  private let transformer: any LLMTransforming
  private let makeSessionID: @Sendable () -> UUID

  public init(
    transformer: any LLMTransforming,
    makeSessionID: @escaping @Sendable () -> UUID = UUID.init
  ) {
    self.transformer = transformer
    self.makeSessionID = makeSessionID
  }

  public func refine(_ request: RefinementRequest) async -> RefinementOutcome {
    let transcript = request.transcript
    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return RefinementOutcome(text: transcript, refined: false)
    }
    guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return RefinementOutcome(
        text: transcript,
        refined: false,
        failure: .llmServerFailure
      )
    }

    do {
      let output = try await transformer.transform(
        LLMRequest(
          instruction: request.composedInstruction,
          selectedText: transcript,
          model: request.model,
          sessionID: makeSessionID(),
          kind: .refinement
        )
      )
      let cleaned = Self.stripWrapping(output)

      guard !cleaned.isEmpty else {
        return RefinementOutcome(
          text: transcript,
          refined: false,
          failure: .llmIncomplete
        )
      }
      guard Self.isPlausibleRewrite(of: transcript, output: cleaned) else {
        return RefinementOutcome(
          text: transcript,
          refined: false,
          failure: .llmIncomplete
        )
      }
      return RefinementOutcome(text: cleaned, refined: true)
    } catch let error as MicAIError {
      return RefinementOutcome(text: transcript, refined: false, failure: error)
    } catch {
      return RefinementOutcome(
        text: transcript,
        refined: false,
        failure: .llmServerFailure
      )
    }
  }

  /// Models sometimes wrap the answer in quotes or a fenced block despite being
  /// told not to. Unwrapping is cheaper than a retry and invisible to the user.
  public static func stripWrapping(_ text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if result.hasPrefix("```") {
      var lines = result.components(separatedBy: "\n")
      lines.removeFirst()
      if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
        lines.removeLast()
      }
      result = lines.joined(separator: "\n").trimmingCharacters(
        in: .whitespacesAndNewlines
      )
    }

    // Only strip quotes wrapping the entire string; a transcript that genuinely
    // opens and closes on quoted speech would otherwise lose them.
    if result.count >= 2, result.hasPrefix("\""), result.hasSuffix("\"") {
      let inner = String(result.dropFirst().dropLast())
      if !inner.contains("\"") {
        result = inner
      }
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Rejects output that grew far beyond the input, which in practice means the
  /// model treated the transcript as a question and answered it.
  public static func isPlausibleRewrite(of transcript: String, output: String) -> Bool {
    let ceiling = max(growthFloor, transcript.count * maximumGrowthFactor)
    return output.count <= ceiling
  }
}
