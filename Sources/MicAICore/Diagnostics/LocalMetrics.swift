import Foundation

public struct LatencyMeasurement: Sendable, Equatable {
  public let mode: MicAIMode
  public let duration: TimeInterval

  public init(mode: MicAIMode, duration: TimeInterval) {
    self.mode = mode
    self.duration = duration
  }
}

public struct LocalMetrics: Sendable {
  public static let capacityPerMode = 20

  private var dictationMeasurements: [LatencyMeasurement] = []
  private var commandMeasurements: [LatencyMeasurement] = []

  public init() {}

  public mutating func record(_ measurement: LatencyMeasurement) {
    switch measurement.mode {
    case .dictation:
      Self.append(measurement, to: &dictationMeasurements)
    case .command:
      Self.append(measurement, to: &commandMeasurements)
    }
  }

  public func last(for mode: MicAIMode) -> LatencyMeasurement? {
    measurements(for: mode).last
  }

  public func median(for mode: MicAIMode) -> LatencyMeasurement? {
    let durations = measurements(for: mode)
      .map(\.duration)
      .sorted()
    guard !durations.isEmpty else {
      return nil
    }

    let midpoint = durations.count / 2
    let duration: TimeInterval
    if durations.count.isMultiple(of: 2) {
      duration = (durations[midpoint - 1] + durations[midpoint]) / 2
    } else {
      duration = durations[midpoint]
    }
    return LatencyMeasurement(mode: mode, duration: duration)
  }

  private func measurements(for mode: MicAIMode) -> [LatencyMeasurement] {
    switch mode {
    case .dictation:
      dictationMeasurements
    case .command:
      commandMeasurements
    }
  }

  private static func append(
    _ measurement: LatencyMeasurement,
    to measurements: inout [LatencyMeasurement]
  ) {
    measurements.append(measurement)
    if measurements.count > capacityPerMode {
      measurements.removeFirst(measurements.count - capacityPerMode)
    }
  }
}
