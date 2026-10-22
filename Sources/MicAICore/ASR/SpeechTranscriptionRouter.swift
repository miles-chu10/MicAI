public protocol SpeechTranscriptionRouting: Sendable {
  func transcribe(
    samples: [Float],
    sampleRate: Int,
    request: SpeechTranscriptionRequest,
    status: @escaping @Sendable (DictationProviderStatus) async -> Void
  ) async throws -> Transcript
}

public actor SpeechTranscriptionRouter: SpeechTranscriptionRouting {
  private let parakeet: any SpeechRecognizing
  private let openAI: any OpenAITranscribing

  public init(
    parakeet: any SpeechRecognizing,
    openAI: any OpenAITranscribing
  ) {
    self.parakeet = parakeet
    self.openAI = openAI
  }

  public func transcribe(
    samples: [Float],
    sampleRate: Int,
    request: SpeechTranscriptionRequest,
    status: @escaping @Sendable (DictationProviderStatus) async -> Void = { _ in }
  ) async throws -> Transcript {
    switch request.provider {
    case .parakeet:
      return try await transcribeWithParakeet(samples: samples, status: status)
    case .openAI:
      return try await transcribeWithOpenAI(
        samples: samples,
        sampleRate: sampleRate,
        request: request,
        status: status
      )
    }
  }

  private func transcribeWithOpenAI(
    samples: [Float],
    sampleRate: Int,
    request: SpeechTranscriptionRequest,
    status: @escaping @Sendable (DictationProviderStatus) async -> Void
  ) async throws -> Transcript {
    await status(.transcribing(.openAI))
    do {
      try Task.checkCancellation()
      let transcript = try await openAI.transcribe(
        samples: samples,
        sampleRate: sampleRate,
        model: request.model
      )
      try Task.checkCancellation()
      await status(.completed(.openAI))
      return transcript
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch let error as MicAIError where error == .cancelled {
      throw error
    } catch {
      let error = (error as? MicAIError) ?? .transcriptionServerFailure
      guard request.fallbackToParakeet else {
        await status(.failed(.openAI, error))
        throw error
      }
      do {
        try Task.checkCancellation()
        await status(.fallingBackToParakeet(error))
        return try await transcribeWithParakeet(samples: samples, status: status)
      } catch is CancellationError {
        throw MicAIError.cancelled
      }
    }
  }

  private func transcribeWithParakeet(
    samples: [Float],
    status: @escaping @Sendable (DictationProviderStatus) async -> Void
  ) async throws -> Transcript {
    await status(.transcribing(.parakeet))
    do {
      try Task.checkCancellation()
      let transcript = try await parakeet.transcribe(samples: samples)
      try Task.checkCancellation()
      await status(.completed(.parakeet))
      return transcript
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch let error as MicAIError where error == .cancelled {
      throw error
    } catch {
      let error = (error as? MicAIError) ?? .asrFailed
      await status(.failed(.parakeet, error))
      throw error
    }
  }
}
