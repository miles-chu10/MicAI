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
    let result = try await runner.run(
      executableURL: URL(fileURLWithPath: "/bin/cat"),
      arguments: [],
      standardInput: largeInput,
      currentDirectoryURL: FileManager.default.temporaryDirectory
    )

    #expect(result.terminationStatus == 0)
    #expect(result.standardOutput == largeInput)
  }
}
