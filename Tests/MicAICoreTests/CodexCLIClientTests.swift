import Foundation
import MicAICore
import Testing

@Suite
struct CodexCLIClientTests {
  @Test
  func keepsUserTextOutOfProcessArgumentsAndReturnsOutput() async throws {
    let runner = CapturingCodexRunner(
      result: CodexCommandResult(
        terminationStatus: 0,
        standardOutput: Data("HELLO\n".utf8),
        standardError: Data()
      )
    )
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let client = CodexCLIClient(
      executableURL: URL(fileURLWithPath: "/usr/bin/true"),
      runner: runner,
      temporaryDirectory: temp
    )

    let sessionID = UUID()
    let output = try await client.transform(
      LLMRequest(
        instruction: "make this uppercase",
        selectedText: "hello",
        model: "gpt-test",
        sessionID: sessionID
      )
    )

    #expect(output == "HELLO")
    let invocation = try #require(await runner.invocation)
    #expect(invocation.arguments.contains("--ephemeral"))
    #expect(invocation.arguments.contains("read-only"))
    #expect(invocation.arguments.contains("shell_tool"))
    #expect(invocation.arguments.contains("gpt-test"))
    #expect(!invocation.arguments.contains { $0.contains("hello") })
    let prompt = try #require(String(data: invocation.standardInput, encoding: .utf8))
    #expect(prompt.contains("\"instruction\":\"make this uppercase\""))
    #expect(prompt.contains("\"selected_text\":\"hello\""))
    #expect(prompt.contains("Never use tools"))
    #expect(invocation.currentDirectoryURL.lastPathComponent.contains(sessionID.uuidString))
    #expect(!FileManager.default.fileExists(atPath: invocation.currentDirectoryURL.path))
  }

  @Test
  func omitsModelFlagWhenUsingSubscriptionDefault() async throws {
    let runner = CapturingCodexRunner(result: .success("done"))
    let client = CodexCLIClient(
      executableURL: URL(fileURLWithPath: "/usr/bin/true"),
      runner: runner
    )

    _ = try await client.transform(
      LLMRequest(instruction: "draft", selectedText: nil, model: "  ")
    )

    let arguments = try #require(await runner.invocation?.arguments)
    #expect(!arguments.contains("--model"))
  }

  @Test
  func missingExecutableReportsSpecificFailure() async {
    let client = CodexCLIClient(
      executableURL: nil,
      runner: CapturingCodexRunner(result: .success("unused"))
    )

    await expectFailure(from: client, is: .codexCLIUnavailable)
  }

  @Test
  func unauthorizedProcessFailureMapsToUnauthorized() async {
    let runner = CapturingCodexRunner(
      result: CodexCommandResult(
        terminationStatus: 1,
        standardOutput: Data(),
        standardError: Data("401 Unauthorized".utf8)
      )
    )
    let client = CodexCLIClient(
      executableURL: URL(fileURLWithPath: "/usr/bin/false"),
      runner: runner
    )

    await expectFailure(from: client, is: .llmUnauthorized)
  }

  @Test
  func timeoutMapsToServerFailure() async {
    let client = CodexCLIClient(
      executableURL: URL(fileURLWithPath: "/usr/bin/true"),
      runner: SuspendingCodexRunner(),
      timeout: .milliseconds(10)
    )

    await expectFailure(from: client, is: .llmServerFailure)
  }

  @Test
  func cancellationMapsToCancelled() async {
    let client = CodexCLIClient(
      executableURL: URL(fileURLWithPath: "/usr/bin/true"),
      runner: SuspendingCodexRunner()
    )
    let task = Task {
      try await client.transform(
        LLMRequest(instruction: "draft", selectedText: nil, model: "")
      )
    }
    await Task.yield()
    task.cancel()

    do {
      _ = try await task.value
      Issue.record("Expected cancellation")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }
  }

  private func expectFailure(
    from client: CodexCLIClient,
    is expected: MicAIError
  ) async {
    do {
      _ = try await client.transform(
        LLMRequest(instruction: "draft", selectedText: nil, model: "gpt-test")
      )
      Issue.record("Expected \(expected)")
    } catch {
      #expect(error as? MicAIError == expected)
    }
  }
}

private struct SuspendingCodexRunner: CodexCommandRunning, Sendable {
  func run(
    executableURL: URL,
    arguments: [String],
    standardInput: Data,
    currentDirectoryURL: URL
  ) async throws -> CodexCommandResult {
    try await Task.sleep(for: .seconds(3_600))
    return .success("unreachable")
  }
}

private actor CapturingCodexRunner: CodexCommandRunning {
  struct Invocation: Sendable {
    let arguments: [String]
    let standardInput: Data
    let currentDirectoryURL: URL
  }

  private let result: CodexCommandResult
  private(set) var invocation: Invocation?

  init(result: CodexCommandResult) {
    self.result = result
  }

  func run(
    executableURL: URL,
    arguments: [String],
    standardInput: Data,
    currentDirectoryURL: URL
  ) async throws -> CodexCommandResult {
    invocation = Invocation(
      arguments: arguments,
      standardInput: standardInput,
      currentDirectoryURL: currentDirectoryURL
    )
    return result
  }
}

extension CodexCommandResult {
  fileprivate static func success(_ output: String) -> Self {
    CodexCommandResult(
      terminationStatus: 0,
      standardOutput: Data(output.utf8),
      standardError: Data()
    )
  }
}
