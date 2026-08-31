import MicAICore
import Testing

@Suite
struct SpeechTranscriptionRouterTests {
  @Test
  func selectsParakeetWithoutTouchingOpenAI() async throws {
    let parakeet = RouterSpeechRecognizer(result: .success(.localFixture))
    let openAI = RouterOpenAITranscriber(result: .success(.remoteFixture))
    let router = SpeechTranscriptionRouter(parakeet: parakeet, openAI: openAI)

    let transcript = try await router.transcribe(
      samples: [0],
      sampleRate: 16_000,
      request: .localParakeet
    )

    #expect(transcript == .localFixture)
    #expect(await parakeet.transcribeCount == 1)
    #expect(await openAI.transcribeCount == 0)
  }

  @Test
  func sendsSelectedOpenAIModelWithoutLocalFallbackOnSuccess() async throws {
    let parakeet = RouterSpeechRecognizer(result: .success(.localFixture))
    let openAI = RouterOpenAITranscriber(result: .success(.remoteFixture))
    let statuses = DictationStatusRecorder()
    let router = SpeechTranscriptionRouter(parakeet: parakeet, openAI: openAI)

    let transcript = try await router.transcribe(
      samples: [0],
      sampleRate: 16_000,
      request: SpeechTranscriptionRequest(
        provider: .openAI,
        model: "custom-transcriber",
        fallbackToParakeet: true
      ),
      status: { status in
        await statuses.record(status)
      }
    )

    #expect(transcript == .remoteFixture)
    #expect(await openAI.models == ["custom-transcriber"])
    #expect(await parakeet.transcribeCount == 0)
    #expect(
      await statuses.values == [
        .transcribing(.openAI),
        .completed(.openAI),
      ]
    )
  }

  @Test
  func fallsBackOnlyWhenEnabled() async throws {
    let enabledLocal = RouterSpeechRecognizer(result: .success(.localFixture))
    let enabledRemote = RouterOpenAITranscriber(
      result: .failure(MicAIError.transcriptionNotConfigured)
    )
    let enabledStatuses = DictationStatusRecorder()
    let enabledRouter = SpeechTranscriptionRouter(
      parakeet: enabledLocal,
      openAI: enabledRemote
    )

    let fallback = try await enabledRouter.transcribe(
      samples: [0],
      sampleRate: 16_000,
      request: SpeechTranscriptionRequest(
        provider: .openAI,
        fallbackToParakeet: true
      ),
      status: { status in
        await enabledStatuses.record(status)
      }
    )
    #expect(fallback == .localFixture)
    #expect(await enabledLocal.transcribeCount == 1)
    #expect(
      await enabledStatuses.values == [
        .transcribing(.openAI),
        .fallingBackToParakeet(.transcriptionNotConfigured),
        .transcribing(.parakeet),
        .completed(.parakeet),
      ]
    )

    let disabledLocal = RouterSpeechRecognizer(result: .success(.localFixture))
    let disabledRouter = SpeechTranscriptionRouter(
      parakeet: disabledLocal,
      openAI: RouterOpenAITranscriber(
        result: .failure(MicAIError.transcriptionNotConfigured)
      )
    )
    await expectError(.transcriptionNotConfigured) {
      try await disabledRouter.transcribe(
        samples: [0],
        sampleRate: 16_000,
        request: SpeechTranscriptionRequest(
          provider: .openAI,
          fallbackToParakeet: false
        )
      )
    }
    #expect(await disabledLocal.transcribeCount == 0)
  }

  @Test
  func cancellationNeverFallsBack() async {
    let local = RouterSpeechRecognizer(result: .success(.localFixture))
    let router = SpeechTranscriptionRouter(
      parakeet: local,
      openAI: RouterOpenAITranscriber(
        result: .failure(MicAIError.cancelled)
      )
    )

    await expectError(.cancelled) {
      try await router.transcribe(
        samples: [0],
        sampleRate: 16_000,
        request: SpeechTranscriptionRequest(
          provider: .openAI,
          fallbackToParakeet: true
        )
      )
    }
    #expect(await local.transcribeCount == 0)
  }

  private func expectError(
    _ expected: MicAIError,
    operation: () async throws -> Transcript
  ) async {
    do {
      _ = try await operation()
      Issue.record("Expected \(expected)")
    } catch {
      #expect(error as? MicAIError == expected)
    }
  }
}

private actor RouterSpeechRecognizer: SpeechRecognizing {
  private let result: Result<Transcript, any Error>
  private(set) var transcribeCount = 0

  init(result: Result<Transcript, any Error>) {
    self.result = result
  }

  func prepare(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws {
    progress(.ready)
  }

  func transcribe(samples: [Float]) async throws -> Transcript {
    transcribeCount += 1
    return try result.get()
  }
}

private actor RouterOpenAITranscriber: OpenAITranscribing {
  private let result: Result<Transcript, any Error>
  private(set) var transcribeCount = 0
  private(set) var models: [String] = []

  init(result: Result<Transcript, any Error>) {
    self.result = result
  }

  func transcribe(
    samples: [Float],
    sampleRate: Int,
    model: String
  ) async throws -> Transcript {
    transcribeCount += 1
    models.append(model)
    return try result.get()
  }
}

private actor DictationStatusRecorder {
  private(set) var values: [DictationProviderStatus] = []

  func record(_ status: DictationProviderStatus) {
    values.append(status)
  }
}

extension Transcript {
  fileprivate static let localFixture = Transcript(
    text: "local",
    audioDuration: 0.5,
    processingDuration: 0.1,
    confidence: 0.9
  )

  fileprivate static let remoteFixture = Transcript(
    text: "remote",
    audioDuration: 0.5,
    processingDuration: 0.2,
    confidence: 0
  )
}
