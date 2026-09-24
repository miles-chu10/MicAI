import Foundation

/// How long one successful operation took, measured from the moment the user
/// released the hotkey, which is the wait they actually feel.
public struct OperationTiming: Sendable, Equatable {
  public let mode: MicAIMode
  /// Hotkey release to transcript ready (local ASR).
  public let transcription: Duration
  /// Time spent waiting on the LLM, if the operation used one.
  public let languageModel: Duration?
  /// Hotkey release to text inserted.
  public let releaseToInsertion: Duration

  public init(
    mode: MicAIMode,
    transcription: Duration,
    languageModel: Duration?,
    releaseToInsertion: Duration
  ) {
    self.mode = mode
    self.transcription = transcription
    self.languageModel = languageModel
    self.releaseToInsertion = releaseToInsertion
  }
}

/// Derives `OperationTiming` from the phase stream the UI already publishes,
/// so measuring needs no hooks inside the pipelines.
///
/// Only a full recording → … → inserting → idle run produces a timing; a
/// failure or cancellation anywhere discards it.
public struct PhaseTimingRecorder: Sendable {
  private var mode: MicAIMode?
  private var released: ContinuousClock.Instant?
  private var transcribed: ContinuousClock.Instant?
  private var llmStarted: ContinuousClock.Instant?
  private var llmFinished: ContinuousClock.Instant?
  private var inserted: ContinuousClock.Instant?
  private var previous: OperationPhase = .idle

  public init() {}

  public mutating func observe(
    _ phase: OperationPhase,
    mode currentMode: MicAIMode?,
    at now: ContinuousClock.Instant
  ) -> OperationTiming? {
    defer { previous = phase }
    switch phase {
    case .recording:
      reset()
      mode = currentMode
    case .transcribing:
      if previous == .recording {
        released = now
      }
    case .awaitingLLM:
      if released != nil, transcribed == nil {
        transcribed = now
        llmStarted = now
      }
    case .inserting:
      if released != nil {
        if transcribed == nil {
          transcribed = now
        } else if llmStarted != nil {
          llmFinished = now
        }
        inserted = now
      }
    case .idle:
      defer { reset() }
      guard previous == .inserting, let mode, let released, let transcribed, inserted != nil
      else {
        return nil
      }
      let languageModel = llmStarted.flatMap { start in llmFinished.map { $0 - start } }
      return OperationTiming(
        mode: mode,
        transcription: transcribed - released,
        languageModel: languageModel,
        releaseToInsertion: now - released
      )
    case .failed:
      reset()
    }
    return nil
  }

  private mutating func reset() {
    mode = nil
    released = nil
    transcribed = nil
    llmStarted = nil
    llmFinished = nil
    inserted = nil
  }
}

/// Recent timings kept in memory only; nothing is written to disk.
public struct LocalMetrics: Sendable, Equatable {
  public static let capacity = 50
  public private(set) var timings: [OperationTiming] = []

  public init() {}

  public mutating func record(_ timing: OperationTiming) {
    timings.append(timing)
    if timings.count > Self.capacity {
      timings.removeFirst(timings.count - Self.capacity)
    }
  }

  public var latest: OperationTiming? {
    timings.last
  }

  public func median(for mode: MicAIMode) -> Duration? {
    let values = timings.filter { $0.mode == mode }.map(\.releaseToInsertion).sorted()
    guard !values.isEmpty else {
      return nil
    }
    let middle = values.count / 2
    return values.count.isMultiple(of: 2)
      ? (values[middle - 1] + values[middle]) / 2
      : values[middle]
  }

  public func worst(for mode: MicAIMode) -> Duration? {
    timings.filter { $0.mode == mode }.map(\.releaseToInsertion).max()
  }
}
