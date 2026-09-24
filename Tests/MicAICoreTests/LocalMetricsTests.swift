import Testing

@testable import MicAICore

struct LocalMetricsTests {
  private let start = ContinuousClock.now

  private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
    start + .milliseconds(milliseconds)
  }

  @Test
  func dictationTimingIsMeasuredFromRelease() {
    var recorder = PhaseTimingRecorder()
    #expect(recorder.observe(.recording, mode: .dictation, at: at(0)) == nil)
    #expect(recorder.observe(.transcribing, mode: .dictation, at: at(10_000)) == nil)
    #expect(recorder.observe(.inserting, mode: .dictation, at: at(10_900)) == nil)
    let timing = recorder.observe(.idle, mode: .dictation, at: at(11_200))

    #expect(
      timing
        == OperationTiming(
          mode: .dictation,
          transcription: .milliseconds(900),
          languageModel: nil,
          releaseToInsertion: .milliseconds(1_200)
        )
    )
  }

  @Test
  func commandTimingSeparatesTheLanguageModelWait() {
    var recorder = PhaseTimingRecorder()
    _ = recorder.observe(.recording, mode: .command, at: at(0))
    _ = recorder.observe(.transcribing, mode: .command, at: at(3_000))
    _ = recorder.observe(.awaitingLLM, mode: .command, at: at(3_400))
    _ = recorder.observe(.inserting, mode: .command, at: at(5_400))
    let timing = recorder.observe(.idle, mode: .command, at: at(5_500))

    #expect(timing?.transcription == .milliseconds(400))
    #expect(timing?.languageModel == .milliseconds(2_000))
    #expect(timing?.releaseToInsertion == .milliseconds(2_500))
  }

  @Test
  func cancellationAndFailureProduceNoTiming() {
    var recorder = PhaseTimingRecorder()
    _ = recorder.observe(.recording, mode: .dictation, at: at(0))
    _ = recorder.observe(.transcribing, mode: .dictation, at: at(1_000))
    #expect(recorder.observe(.idle, mode: nil, at: at(1_100)) == nil)

    _ = recorder.observe(.recording, mode: .dictation, at: at(2_000))
    _ = recorder.observe(.transcribing, mode: .dictation, at: at(3_000))
    _ = recorder.observe(.inserting, mode: .dictation, at: at(3_500))
    _ = recorder.observe(.failed(.insertionFailed), mode: .dictation, at: at(3_600))
    #expect(recorder.observe(.idle, mode: nil, at: at(3_700)) == nil)
  }

  @Test
  func medianAndWorstArePerModeAndBounded() {
    var metrics = LocalMetrics()
    for milliseconds in [900, 1_500, 1_100] {
      metrics.record(
        OperationTiming(
          mode: .dictation,
          transcription: .milliseconds(milliseconds),
          languageModel: nil,
          releaseToInsertion: .milliseconds(milliseconds)
        )
      )
    }
    #expect(metrics.median(for: .dictation) == .milliseconds(1_100))
    #expect(metrics.worst(for: .dictation) == .milliseconds(1_500))
    #expect(metrics.median(for: .command) == nil)

    for _ in 0..<(LocalMetrics.capacity + 5) {
      metrics.record(metrics.latest!)
    }
    #expect(metrics.timings.count == LocalMetrics.capacity)
  }
}
