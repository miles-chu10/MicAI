import Foundation

public actor DictationPipeline {
  private struct Context: Sendable {
    let mode: MicAIMode
    let transcriptionRequest: SpeechTranscriptionRequest
  }

  private static let requiredSampleRate = 16_000
  private static let minimumSampleCount = 4_800

  private let audioCapture: any AudioCapturing
  private let recognizer: any SpeechRecognizing
  private let transcriptionRouter: (any SpeechTranscriptionRouting)?
  private let cleaner: any TranscriptCleaning
  private let coordinator: OperationCoordinator
  private var contexts: [UUID: Context] = [:]

  public init(
    audioCapture: any AudioCapturing,
    recognizer: any SpeechRecognizing,
    transcriptionRouter: (any SpeechTranscriptionRouting)? = nil,
    cleaner: any TranscriptCleaning,
    coordinator: OperationCoordinator
  ) {
    self.audioCapture = audioCapture
    self.recognizer = recognizer
    self.transcriptionRouter = transcriptionRouter
    self.cleaner = cleaner
    self.coordinator = coordinator
  }

  public func begin(
    mode: MicAIMode = .dictation,
    target: TargetIdentity,
    transcriptionRequest: SpeechTranscriptionRequest? = nil,
    levels: @escaping @Sendable (Float) -> Void,
    maximumDurationReached: @escaping @Sendable () -> Void = {},
    operationStarted: @escaping @Sendable (UUID) async -> Void = { _ in }
  ) async throws -> UUID {
    let operationID = try await coordinator.begin(mode: mode, target: target)
    contexts[operationID] = Context(
      mode: mode,
      transcriptionRequest: transcriptionRequest ?? .localParakeet
    )
    await operationStarted(operationID)
    do {
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      try await audioCapture.start(
        levels: levels,
        maximumDurationReached: maximumDurationReached
      )
      guard await coordinator.isCurrent(operationID: operationID) else {
        await audioCapture.cancel()
        throw MicAIError.cancelled
      }
      return operationID
    } catch let error as MicAIError {
      contexts.removeValue(forKey: operationID)
      _ = await coordinator.fail(operationID: operationID, error: error)
      throw error
    } catch {
      contexts.removeValue(forKey: operationID)
      _ = await coordinator.fail(operationID: operationID, error: .audioUnavailable)
      throw MicAIError.audioUnavailable
    }
  }

  public func finish(
    operationID: UUID,
    providerStatus:
      @escaping @Sendable (
        UUID,
        DictationProviderStatus
      ) async -> Void = { _, _ in }
  ) async throws -> Transcript {
    guard let context = contexts.removeValue(forKey: operationID) else {
      throw MicAIError.invalidTransition
    }
    let audio: RecordedAudio
    do {
      audio = try await audioCapture.stop()
    } catch {
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      _ = await coordinator.fail(operationID: operationID, error: .audioUnavailable)
      throw MicAIError.audioUnavailable
    }
    guard audio.sampleRate == Self.requiredSampleRate else {
      _ = await coordinator.fail(operationID: operationID, error: .audioUnavailable)
      throw MicAIError.audioUnavailable
    }
    guard audio.samples.count >= Self.minimumSampleCount else {
      _ = await coordinator.fail(operationID: operationID, error: .audioTooShort)
      throw MicAIError.audioTooShort
    }

    await coordinator.stopRecording(operationID: operationID)
    guard await coordinator.isCurrent(operationID: operationID) else {
      throw MicAIError.cancelled
    }

    let recognizer = self.recognizer
    let transcriptionRouter = self.transcriptionRouter
    let cleaner = self.cleaner
    let task = Task<Transcript, Error> {
      try Task.checkCancellation()
      let transcript: Transcript
      if context.mode == .dictation, let transcriptionRouter {
        transcript = try await transcriptionRouter.transcribe(
          samples: audio.samples,
          sampleRate: audio.sampleRate,
          request: context.transcriptionRequest,
          status: { status in
            await providerStatus(operationID, status)
          }
        )
      } else {
        transcript = try await recognizer.transcribe(samples: audio.samples)
      }
      try Task.checkCancellation()
      let cleanedText = cleaner.clean(transcript.text)
      guard !cleanedText.isEmpty else {
        throw MicAIError.asrFailed
      }
      return Transcript(
        text: cleanedText,
        audioDuration: transcript.audioDuration,
        processingDuration: transcript.processingDuration,
        confidence: transcript.confidence
      )
    }
    guard
      await coordinator.registerCancellationHandler(
        { task.cancel() },
        operationID: operationID
      )
    else {
      throw MicAIError.cancelled
    }

    do {
      let transcript = try await task.value
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      return transcript
    } catch let error as MicAIError {
      if await coordinator.isCurrent(operationID: operationID) {
        _ = await coordinator.fail(operationID: operationID, error: error)
      }
      throw error
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch {
      if await coordinator.isCurrent(operationID: operationID) {
        _ = await coordinator.fail(operationID: operationID, error: .asrFailed)
      }
      throw MicAIError.asrFailed
    }
  }

  public func cancel(operationID: UUID) async {
    contexts.removeValue(forKey: operationID)
    await audioCapture.cancel()
    await coordinator.cancel(operationID: operationID)
  }
}
