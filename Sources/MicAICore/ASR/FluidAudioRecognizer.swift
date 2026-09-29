import FluidAudio
import Foundation

public actor FluidAudioRecognizer: SpeechRecognizing {
  private static let minimumSampleCount = 4_800

  private var manager: AsrManager?
  private var preparationTask: Task<AsrManager, Error>?
  private var observers: [UUID: @Sendable (ModelPreparationState) -> Void] = [:]
  private var preparationState: ModelPreparationState = .notDownloaded
  private var choice: SpeechModelChoice

  public init(model: SpeechModelChoice = .english) {
    choice = model
  }

  public var model: SpeechModelChoice {
    choice
  }

  /// Switches the model that the next `prepare` loads. The loaded manager is
  /// dropped, so a dictation never runs on a model the user switched away
  /// from; the caller re-prepares, which is instant when the new model is
  /// already cached.
  public func select(_ model: SpeechModelChoice) {
    guard model != choice else {
      return
    }
    choice = model
    manager = nil
    preparationTask?.cancel()
    preparationTask = nil
    publish(.notDownloaded)
  }

  private var version: AsrModelVersion {
    switch choice {
    case .english:
      .v2
    case .multilingual:
      .v3
    }
  }

  public func prepareCachedIfAvailable(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws -> Bool {
    let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
    guard
      AsrModels.modelsExist(
        at: cacheDirectory,
        version: version,
        encoderPrecision: .int8
      )
    else {
      return false
    }
    try await prepare(progress: progress)
    return true
  }

  public func prepare(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws {
    let observerID = UUID()
    observers[observerID] = progress
    defer { observers.removeValue(forKey: observerID) }

    if manager != nil {
      progress(.ready)
      return
    }

    let task: Task<AsrManager, Error>
    if let preparationTask {
      task = preparationTask
      progress(preparationState)
    } else {
      publish(.preparing(fraction: 0, phase: "Listing model files"))
      let recognizer = self
      let version = self.version
      let newTask = Task {
        let models = try await AsrModels.downloadAndLoad(
          version: version,
          progressHandler: { downloadProgress in
            let state = Self.map(downloadProgress)
            Task { await recognizer.publish(state) }
          }
        )
        let manager = AsrManager(config: .default, models: models)
        guard await manager.isAvailable else {
          throw MicAIError.asrNotInitialized
        }
        return manager
      }
      preparationTask = newTask
      task = newTask
    }

    let requested = choice
    let loaded: AsrManager
    do {
      loaded = try await task.value
    } catch {
      // A switch to another model while this one was loading already reset
      // the state for the new model; reporting this failure would overwrite it.
      guard choice == requested else {
        throw MicAIError.cancelled
      }
      preparationTask = nil
      if error is CancellationError {
        publish(.failed("Model preparation was cancelled."))
        throw MicAIError.cancelled
      }
      publish(.failed("Model preparation failed."))
      throw MicAIError.modelDownloadFailed
    }
    // The user may have switched models while this one was downloading.
    // Keeping it would mean dictating with the model they just turned off.
    guard choice == requested else {
      throw MicAIError.cancelled
    }
    manager = loaded
    preparationTask = nil
    publish(.ready)
  }

  public func transcribe(samples: [Float]) async throws -> Transcript {
    guard samples.count >= Self.minimumSampleCount else {
      throw MicAIError.audioTooShort
    }
    guard let manager else {
      throw MicAIError.asrNotInitialized
    }

    do {
      try Task.checkCancellation()
      var decoderState = try TdtDecoderState()
      let result = try await manager.transcribe(
        samples,
        decoderState: &decoderState,
        language: nil
      )
      try Task.checkCancellation()

      guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw MicAIError.asrFailed
      }
      return Transcript(
        text: result.text,
        audioDuration: result.duration,
        processingDuration: result.processingTime,
        confidence: result.confidence
      )
    } catch let error as MicAIError {
      throw error
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch {
      throw MicAIError.asrFailed
    }
  }

  public func state() -> ModelPreparationState {
    preparationState
  }

  private func publish(_ state: ModelPreparationState) {
    preparationState = state
    for observer in observers.values {
      observer(state)
    }
  }

  private nonisolated static func map(_ progress: DownloadProgress) -> ModelPreparationState {
    let phase: String
    switch progress.phase {
    case .listing:
      phase = "Listing model files"
    case .downloading(let completedFiles, let totalFiles):
      phase = "Downloading \(completedFiles) of \(totalFiles) files"
    case .compiling(let modelName):
      phase = "Compiling \(modelName)"
    }
    return .preparing(fraction: progress.fractionCompleted, phase: phase)
  }
}
