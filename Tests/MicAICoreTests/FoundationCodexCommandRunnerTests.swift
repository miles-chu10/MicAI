import Foundation
import Testing

@testable import MicAICore

/// Runs real child processes: the fake runner used elsewhere cannot catch
/// pipe-level failures.
struct FoundationCodexCommandRunnerTests {
  private let largeInput = Data(repeating: UInt8(ascii: "a"), count: 1_048_576)
  private let runner = FoundationCodexCommandRunner()

  @Test
  func childThatNeverReadsItsInputDoesNotKillTheCaller() async throws {
    let result = try await runner.run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "exit 3"],
      standardInput: largeInput,
      currentDirectoryURL: FileManager.default.temporaryDirectory
    )

    #expect(result.terminationStatus == 3)
  }

  @Test
  func inputLargerThanThePipeBufferRoundTripsWithoutDeadlock() async throws {
    // cat echoes the 1 MiB input, so this run allows that much output.
    let echoing = FoundationCodexCommandRunner(
      limits: CodexOutputLimits(standardOutput: 2 * 1_048_576)
    )
    let result = try await echoing.run(
      executableURL: URL(fileURLWithPath: "/bin/cat"),
      arguments: [],
      standardInput: largeInput,
      currentDirectoryURL: FileManager.default.temporaryDirectory
    )

    #expect(result.terminationStatus == 0)
    #expect(result.standardOutput == largeInput)
  }

  // MARK: - Output limits

  private func sh(
    _ script: String,
    limits: CodexOutputLimits
  ) async throws -> CodexCommandResult {
    try await FoundationCodexCommandRunner(limits: limits).run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", script],
      standardInput: Data(),
      currentDirectoryURL: FileManager.default.temporaryDirectory
    )
  }

  @Test
  func outputExactlyAtTheLimitIsReturnedWhole() async throws {
    let result = try await sh(
      "head -c 1000 /dev/zero",
      limits: CodexOutputLimits(standardOutput: 1_000, standardError: 100)
    )
    #expect(result.terminationStatus == 0)
    #expect(result.standardOutput.count == 1_000)
  }

  @Test
  func oneByteOverTheLimitIsRejectedNotTruncated() async {
    await #expect(throws: MicAIError.llmOutputTooLarge) {
      _ = try await sh(
        "head -c 1001 /dev/zero",
        limits: CodexOutputLimits(standardOutput: 1_000, standardError: 100)
      )
    }
  }

  @Test
  func aChildThatNeverStopsWritingIsStoppedAndRejected() async {
    let started = ContinuousClock.now
    await #expect(throws: MicAIError.llmOutputTooLarge) {
      _ = try await sh(
        "exec yes",
        limits: CodexOutputLimits(standardOutput: 4_096, standardError: 100)
      )
    }
    #expect(ContinuousClock.now - started < .seconds(10))
  }

  @Test
  func bothPipesFillingAtOnceDoNotDeadlockAndStderrIsCapped() async throws {
    // Each stream is larger than a pipe buffer, so reading them one after the
    // other would hang.
    let result = try await sh(
      "head -c 200000 /dev/zero >&2 & head -c 200000 /dev/zero; wait",
      limits: CodexOutputLimits(standardOutput: 256 * 1_024, standardError: 1_024)
    )
    #expect(result.terminationStatus == 0)
    #expect(result.standardOutput.count == 200_000)
    #expect(result.standardError.count == 1_024)
  }

  @Test
  func defaultLimitsAreTheDocumentedOnes() {
    let limits = CodexOutputLimits()
    #expect(limits.standardOutput == 262_144)
    #expect(limits.standardError == 65_536)
  }

  @Test
  func cancellingStopsTheChildPromptly() async {
    let started = ContinuousClock.now
    let task = Task {
      try await sh("exec sleep 30", limits: CodexOutputLimits())
    }
    try? await Task.sleep(for: .milliseconds(200))
    task.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
    #expect(ContinuousClock.now - started < .seconds(10))
  }
}
