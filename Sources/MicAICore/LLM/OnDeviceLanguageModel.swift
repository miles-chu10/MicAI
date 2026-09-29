import Foundation

#if canImport(FoundationModels)
  // Weak so the app still launches on macOS 14 and 15, where the framework
  // does not exist. Every use below is behind an availability check.
  @_weakLinked import FoundationModels
#endif

/// Apple's on-device language model, for clean-up that never leaves the Mac.
///
/// Requires macOS 26 with Apple Intelligence turned on. Builds made with an
/// older SDK compile this out entirely and report it as unavailable.
public enum OnDeviceLanguageModel {
  /// `RefinementEngine` needs a model name to send; the on-device model has
  /// none, so this stands in for it.
  public static let modelName = "apple-on-device"

  /// Why the model cannot run right now, or nil when it can. Checked live,
  /// because Apple Intelligence can be turned on or off at any time.
  public static var unavailableReason: String? {
    #if canImport(FoundationModels)
      guard #available(macOS 26.0, *) else {
        return "Needs macOS 26 or later."
      }
      return reason(for: SystemLanguageModel.default.availability)
    #else
      return "This build of MicAI doesn’t include Apple Intelligence support."
    #endif
  }

  public static var isAvailable: Bool {
    unavailableReason == nil
  }

  /// A transformer backed by the on-device model, or nil when this build or
  /// this version of macOS cannot have one. Whether Apple Intelligence is on
  /// is checked on every request instead, since it can change while MicAI runs.
  public static func makeTransformer() -> (any LLMTransforming)? {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return AppleOnDeviceTransformer()
      }
    #endif
    return nil
  }

  /// The prompt for a request: the same two fields the network path sends,
  /// named the way the shared system instructions refer to them. The text is
  /// fenced so a dictated "ignore your instructions" stays data.
  public static func prompt(for request: LLMRequest) -> String {
    var parts = ["instruction:\n\(request.instruction)"]
    if let selectedText = request.selectedText {
      parts.append("selected_text:\n<<<\n\(selectedText)\n>>>")
    }
    return parts.joined(separator: "\n\n")
  }

  #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func reason(for availability: SystemLanguageModel.Availability) -> String? {
      switch availability {
      case .available:
        return nil
      case .unavailable(.deviceNotEligible):
        return "This Mac can’t run Apple Intelligence."
      case .unavailable(.appleIntelligenceNotEnabled):
        return "Turn on Apple Intelligence in System Settings."
      case .unavailable(.modelNotReady):
        return "Apple Intelligence is still getting its model ready."
      case .unavailable:
        return "Apple Intelligence isn’t available right now."
      }
    }
  #endif
}

#if canImport(FoundationModels)
  /// Runs a request through a fresh on-device session. Fresh each time: a
  /// dictation must not be shaped by the one before it.
  @available(macOS 26.0, *)
  struct AppleOnDeviceTransformer: LLMTransforming {
    func transform(_ request: LLMRequest) async throws -> String {
      let model = SystemLanguageModel.default
      guard model.isAvailable else {
        throw MicAIError.onDeviceModelUnavailable
      }
      let session = LanguageModelSession(
        model: model,
        instructions: ResponsesRequest.instructions(for: request.kind)
      )
      do {
        let response = try await session.respond(
          to: OnDeviceLanguageModel.prompt(for: request),
          options: GenerationOptions(temperature: 0.2)
        )
        return response.content
      } catch is CancellationError {
        throw MicAIError.cancelled
      } catch {
        // Guardrail refusals and an over-long transcript land here. Either
        // way the caller keeps the words as spoken.
        throw MicAIError.llmIncomplete
      }
    }
  }
#endif
