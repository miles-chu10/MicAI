import FluidAudio
import Foundation

public actor FluidAudioRecognizer: SpeechRecognizing {
  private static let minimumSampleCount = 4_800

  private var manager: AsrManager?
  private var preparationTask: Task<AsrManager, Error>?
  private var observers: [UUID: @Sendable (ModelPreparationState) -> Void] = [:]
  private var preparationState: ModelPreparationState = .notDownloaded

  public init() {}

  public func prepareCachedIfAvailable(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws -> Bool {
    let cacheDirectory = AsrModels.defaultCacheDirectory(for: .v2)
    guard
      AsrModels.modelsExist(
        at: cacheDirectory,
        version: .v2,
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
      let newTask = Task {
        let models = try await AsrModels.downloadAndLoad(
          version: .v2,
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

    do {
      manager = try await task.value
      preparationTask = nil
      publish(.ready)
    } catch is CancellationError {
      preparationTask = nil
      publish(.failed("Model preparation was cancelled."))
      throw MicAIError.cancelled
    } catch {
      preparationTask = nil
      publish(.failed("Model preparation failed."))
      throw MicAIError.modelDownloadFailed
    }
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
