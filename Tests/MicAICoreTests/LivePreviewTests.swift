import Foundation
import MicAICore
import Testing

@Suite
struct LivePreviewTests {
  private let target = TargetIdentity(processIdentifier: 7)

  @Test
  func partialsArriveWhileRecordingAndStopBeforeTheFinalPass() async throws {
    let audio = GrowingAudioCapture()
    let recognizer = CountingRecognizer()
    let partials = PartialLog()
    let pipeline = DictationPipeline(
      audioCapture: audio,
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: OperationCoordinator(),
      previewInterval: .milliseconds(5)
    )

    let operationID = try await pipeline.begin(
      target: target,
      levels: { _ in },
      partials: { text in partials.append(text) }
    )
    try await waitUntil { partials.count >= 2 }

    let transcript = try await pipeline.finish(operationID: operationID)
    let countAtFinish = partials.count
    try await Task.sleep(for: .milliseconds(40))

    #expect(transcript.text == "heard so far")
    #expect(partials.entries.first == "heard so far")
    // The preview and the final pass share the recognizer and must never run
    // at the same time.
    #expect(await recognizer.maximumConcurrent == 1)
    // Nothing is previewed once finishing has started.
    #expect(partials.count == countAtFinish)
  }

  @Test
  func withoutAPartialsHandlerNothingIsPreviewed() async throws {
    let audio = GrowingAudioCapture()
    let recognizer = CountingRecognizer()
    let pipeline = DictationPipeline(
      audioCapture: audio,
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: OperationCoordinator(),
      previewInterval: .milliseconds(5)
    )

    let operationID = try await pipeline.begin(target: target) { _ in }
    try await Task.sleep(for: .milliseconds(40))
    _ = try await pipeline.finish(operationID: operationID)

    #expect(await audio.snapshotCount == 0)
    #expect(await recognizer.callCount == 1)
  }

  @Test
  func longRecordingsPreviewOnlyTheNewestAudioAndSaySo() async throws {
    let audio = GrowingAudioCapture(total: .seconds(45))
    let partials = PartialLog()
    let pipeline = DictationPipeline(
      audioCapture: audio,
      recognizer: CountingRecognizer(),
      cleaner: TranscriptCleaner(),
      coordinator: OperationCoordinator(),
      previewInterval: .milliseconds(5)
    )

    let operationID = try await pipeline.begin(
      target: target,
      levels: { _ in },
      partials: { text in partials.append(text) }
    )
    try await waitUntil { partials.count >= 1 }
    await pipeline.cancel(operationID: operationID)

    #expect(partials.entries.first == "…heard so far")
    #expect(await audio.requestedTail == DictationPipeline.previewWindow)
  }

  @Test
  func cancellingStopsThePreview() async throws {
    let audio = GrowingAudioCapture()
    let partials = PartialLog()
    let pipeline = DictationPipeline(
      audioCapture: audio,
      recognizer: CountingRecognizer(),
      cleaner: TranscriptCleaner(),
      coordinator: OperationCoordinator(),
      previewInterval: .milliseconds(5)
    )

    let operationID = try await pipeline.begin(
      target: target,
      levels: { _ in },
      partials: { text in partials.append(text) }
    )
    try await waitUntil { partials.count >= 1 }
    await pipeline.cancel(operationID: operationID)
    let snapshotsAtCancel = await audio.snapshotCount
    try await Task.sleep(for: .milliseconds(40))

    #expect(await audio.snapshotCount == snapshotsAtCancel)
  }

  private func waitUntil(
    _ condition: () async -> Bool,
    timeout: Duration = .seconds(5)
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
      guard clock.now < deadline else {
        Issue.record("Timed out waiting for a condition")
        return
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }
}

/// A recording that grows by a tenth of a second on every snapshot.
private actor GrowingAudioCapture: AudioCapturing {
  private var elapsed: Duration
  private(set) var snapshotCount = 0
  private(set) var requestedTail: Duration?

  init(total: Duration = .seconds(1)) {
    elapsed = total
  }

  func start(levels: @escaping @Sendable (Float) -> Void) async throws {}

  func stop() async throws -> RecordedAudio {
    RecordedAudio(
      samples: [Float](repeating: 0.1, count: 16_000),
      sampleRate: 16_000,
      duration: .seconds(1)
    )
  }

  func cancel() async {}

  func snapshot(tail: Duration) async -> AudioSnapshot? {
    snapshotCount += 1
    requestedTail = tail
    elapsed += .milliseconds(100)
    return AudioSnapshot(
      samples: [Float](repeating: 0.1, count: 8_000),
      totalDuration: elapsed
    )
  }
}

/// Records how many transcriptions overlap.
private actor CountingRecognizer: SpeechRecognizing {
  private var inFlight = 0
  private(set) var maximumConcurrent = 0
  private(set) var callCount = 0

  func prepare(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws {
    progress(.ready)
  }

  func transcribe(samples: [Float]) async throws -> Transcript {
    callCount += 1
    inFlight += 1
    maximumConcurrent = max(maximumConcurrent, inFlight)
    // Suspends so an overlapping call, if the pipeline allowed one, would
    // actually overlap here.
    try? await Task.sleep(for: .milliseconds(3))
    inFlight -= 1
    return Transcript(
      text: "heard so far",
      audioDuration: 1,
      processingDuration: 0.01,
      confidence: 0.9
    )
  }
}

/// Recorded synchronously, so a count read after `finish` returns cannot be
/// raced by an append still on its way.
private final class PartialLog: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  var entries: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  var count: Int {
    entries.count
  }

  func append(_ text: String) {
    lock.lock()
    storage.append(text)
    lock.unlock()
  }
}
