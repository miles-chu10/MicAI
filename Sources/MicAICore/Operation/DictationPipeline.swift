import Foundation

public actor DictationPipeline {
  private static let requiredSampleRate = 16_000
  private static let minimumSampleCount = 4_800
  /// How often live preview re-reads what has been said so far.
  public static let defaultPreviewInterval: Duration = .milliseconds(800)
  /// Live preview transcribes at most this much of the newest audio, so its
  /// cost stays flat however long the dictation runs.
  public static let previewWindow: Duration = .seconds(20)

  private let audioCapture: any AudioCapturing
  private let recognizer: any SpeechRecognizing
  private let cleaner: any TranscriptCleaning
  private let coordinator: OperationCoordinator
  private let previewInterval: Duration
  private var previews: [UUID: Task<Void, Never>] = [:]

  public init(
    audioCapture: any AudioCapturing,
    recognizer: any SpeechRecognizing,
    cleaner: any TranscriptCleaning,
    coordinator: OperationCoordinator,
    previewInterval: Duration = DictationPipeline.defaultPreviewInterval
  ) {
    self.audioCapture = audioCapture
    self.recognizer = recognizer
    self.cleaner = cleaner
    self.coordinator = coordinator
    self.previewInterval = previewInterval
  }

  /// Starts recording. With `partials`, a rough transcript of what has been
  /// said so far is delivered about once per `previewInterval` while
  /// recording, for the HUD. The text that gets inserted never comes from the
  /// preview: `finish` always transcribes the whole recording in one pass.
  public func begin(
    mode: MicAIMode = .dictation,
    target: TargetIdentity,
    levels: @escaping @Sendable (Float) -> Void,
    operationStarted: @escaping @Sendable (UUID) async -> Void = { _ in },
    partials: (@Sendable (String) -> Void)? = nil
  ) async throws -> UUID {
    let operationID = try await coordinator.begin(mode: mode, target: target)
    await operationStarted(operationID)
    do {
      try await audioCapture.start(levels: levels)
      guard await coordinator.isCurrent(operationID: operationID) else {
        await audioCapture.cancel()
        throw MicAIError.cancelled
      }
      if let partials {
        previews[operationID] = makePreview(partials)
      }
      return operationID
    } catch let error as MicAIError {
      _ = await coordinator.fail(operationID: operationID, error: error)
      throw error
    } catch {
      _ = await coordinator.fail(operationID: operationID, error: .audioUnavailable)
      throw MicAIError.audioUnavailable
    }
  }

  public func finish(operationID: UUID) async throws -> Transcript {
    // The preview shares the recognizer. Waiting for it to finish means the
    // final pass never runs alongside a preview pass.
    await stopPreview(operationID)
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
    let cleaner = self.cleaner
    let task = Task<Transcript, Error> {
      try Task.checkCancellation()
      let transcript = try await recognizer.transcribe(samples: audio.samples)
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
    await stopPreview(operationID)
    await audioCapture.cancel()
    await coordinator.cancel(operationID: operationID)
  }

  private func makePreview(
    _ partials: @escaping @Sendable (String) -> Void
  ) -> Task<Void, Never> {
    let audioCapture = self.audioCapture
    let recognizer = self.recognizer
    let cleaner = self.cleaner
    let interval = previewInterval
    return Task {
      var lastDuration = Duration.zero
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled,
          let snapshot = await audioCapture.snapshot(tail: Self.previewWindow),
          snapshot.samples.count >= Self.minimumSampleCount,
          snapshot.totalDuration > lastDuration
        else {
          continue
        }
        lastDuration = snapshot.totalDuration
        // A failed preview pass is not worth reporting: the final pass is the
        // one that matters, and the next preview pass is under a second away.
        guard let transcript = try? await recognizer.transcribe(samples: snapshot.samples),
          !Task.isCancelled
        else {
          continue
        }
        let text = cleaner.clean(transcript.text)
        guard !text.isEmpty else {
          continue
        }
        let truncated = snapshot.totalDuration > Self.previewWindow
        partials(truncated ? "…" + text : text)
      }
    }
  }

  private func stopPreview(_ operationID: UUID) async {
    guard let preview = previews.removeValue(forKey: operationID) else {
      return
    }
    preview.cancel()
    await preview.value
  }
}
