import MicAICore
import Testing

@Suite
struct LocalMetricsTests {
  @Test
  func recordsLastMeasurementPerMode() {
    var metrics = LocalMetrics()

    metrics.record(LatencyMeasurement(mode: .dictation, duration: 1.2))
    metrics.record(LatencyMeasurement(mode: .command, duration: 2.4))
    metrics.record(LatencyMeasurement(mode: .dictation, duration: 0.8))

    #expect(
      metrics.last(for: .dictation)
        == LatencyMeasurement(mode: .dictation, duration: 0.8)
    )
    #expect(
      metrics.last(for: .command)
        == LatencyMeasurement(mode: .command, duration: 2.4)
    )
  }

  @Test
  func medianHandlesOddAndEvenCounts() {
    var metrics = LocalMetrics()
    metrics.record(LatencyMeasurement(mode: .dictation, duration: 3))
    metrics.record(LatencyMeasurement(mode: .dictation, duration: 1))
    metrics.record(LatencyMeasurement(mode: .dictation, duration: 2))

    #expect(metrics.median(for: .dictation)?.duration == 2)

    metrics.record(LatencyMeasurement(mode: .dictation, duration: 4))

    #expect(metrics.median(for: .dictation)?.duration == 2.5)
  }

  @Test
  func emptyModeHasNoMeasurements() {
    let metrics = LocalMetrics()

    #expect(metrics.last(for: .command) == nil)
    #expect(metrics.median(for: .command) == nil)
  }

  @Test
  func retainsOnlyTheLastTwentyMeasurementsPerMode() {
    var metrics = LocalMetrics()

    for duration in 0..<25 {
      metrics.record(
        LatencyMeasurement(
          mode: .command,
          duration: Double(duration)
        )
      )
    }

    #expect(metrics.last(for: .command)?.duration == 24)
    #expect(metrics.median(for: .command)?.duration == 14.5)
  }
}
