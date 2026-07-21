import MicAICore
import Testing

@Suite
struct DictationPipelineTests {
  private let target = TargetIdentity(processIdentifier: 42)

  @Test
  func captureFlowsThroughRecognitionAndCleanup() async throws {
    let audio = FakeAudioCapture()
    let recognizer = FakeSpeechRecognizer(
      transcript: Transcript(
        text: "  hello   world  ",
        audioDuration: 0.5,
        processingDuration: 0.1,
        confidence: 0.9
      )
    )
    let coordinator = OperationCoordinator()
    let pipeline = DictationPipeline(
      audioCapture: audio,
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: coordinator
    )

    let operationID = try await pipeline.begin(target: target) { _ in }
    let transcript = try await pipeline.finish(operationID: operationID)

    #expect(transcript.text == "hello world")
    #expect(await audio.startCount == 1)
    #expect(await audio.stopCount == 1)
    #expect(await recognizer.transcribeCount == 1)
    #expect(await coordinator.snapshot().phase == .transcribing)
  }

  @Test
  func rejectsTooShortAudioBeforeRecognition() async throws {
    let audio = FakeAudioCapture(sampleCount: 4_799)
    let recognizer = FakeSpeechRecognizer(transcript: .fixture)
    let coordinator = OperationCoordinator()
    let pipeline = DictationPipeline(
      audioCapture: audio,
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: coordinator
    )
    let operationID = try await pipeline.begin(target: target) { _ in }

    do {
      _ = try await pipeline.finish(operationID: operationID)
      Issue.record("Expected short audio to be rejected")
    } catch {
      #expect(error as? MicAIError == .audioTooShort)
    }
    #expect(await recognizer.transcribeCount == 0)
  }

  @Test
  func cancellationStopsCaptureAndMakesLateResultInert() async throws {
    let audio = FakeAudioCapture()
    let recognizer = DeferredSpeechRecognizer()
    let coordinator = OperationCoordinator()
    let pipeline = DictationPipeline(
      audioCapture: audio,
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: coordinator
    )
    let operationID = try await pipeline.begin(target: target) { _ in }
    let finishTask = Task {
      try await pipeline.finish(operationID: operationID)
    }

    while !(await recognizer.hasStarted) {
      await Task.yield()
    }
    await pipeline.cancel(operationID: operationID)
    await recognizer.release(.fixture)

    do {
      _ = try await finishTask.value
      Issue.record("Expected cancelled recognition to remain inert")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }
    #expect(await audio.cancelCount == 1)
    #expect(await coordinator.snapshot().phase == .idle)
  }
}

private actor FakeAudioCapture: AudioCapturing {
  private let sampleCount: Int
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var cancelCount = 0

  init(sampleCount: Int = 8_000) {
    self.sampleCount = sampleCount
  }

  func start(levels: @escaping @Sendable (Float) -> Void) async throws {
    startCount += 1
    levels(0.5)
  }

  func stop() async throws -> RecordedAudio {
    stopCount += 1
    return RecordedAudio(
      samples: [Float](repeating: 0.1, count: sampleCount),
      sampleRate: 16_000,
      duration: .seconds(Double(sampleCount) / 16_000)
    )
  }

  func cancel() async {
    cancelCount += 1
  }
}

private actor FakeSpeechRecognizer: SpeechRecognizing {
  private let transcript: Transcript
  private(set) var transcribeCount = 0

  init(transcript: Transcript) {
    self.transcript = transcript
  }

  func prepare(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws {
    progress(.ready)
  }

  func transcribe(samples: [Float]) async throws -> Transcript {
    transcribeCount += 1
    return transcript
  }
}

private actor DeferredSpeechRecognizer: SpeechRecognizing {
  private var continuation: CheckedContinuation<Transcript, Never>?
  private(set) var hasStarted = false

  func prepare(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws {
    progress(.ready)
  }

  func transcribe(samples: [Float]) async throws -> Transcript {
    hasStarted = true
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func release(_ transcript: Transcript) {
    continuation?.resume(returning: transcript)
    continuation = nil
  }
}

extension Transcript {
  fileprivate static let fixture = Transcript(
    text: "hello",
    audioDuration: 0.5,
    processingDuration: 0.1,
    confidence: 0.9
  )
}
