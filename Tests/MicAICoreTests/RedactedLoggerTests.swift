import MicAICore
import Testing

@Suite
struct RedactedLoggerTests {
  @Test
  func messagesContainOnlyLifecycleIdentifiers() {
    let sentinel = "SENSITIVE_USER_CONTENT_SENTINEL"
    let events: [RedactedEvent] = [
      .operationStarted(mode: .dictation),
      .phaseChanged(mode: .command, phase: .awaitingLLM),
      .operationCompleted(mode: .dictation),
      .operationFailed(mode: .command, error: .llmUnauthorized),
      .operationCancelled(mode: .command),
    ]

    let messages = events.map { RedactedLogger.message(for: $0) }

    #expect(messages.count == 5)
    #expect(messages.allSatisfy { !$0.contains(sentinel) })
    #expect(messages[0] == "operationStarted mode=dictation")
    #expect(messages[1] == "phaseChanged mode=command phase=awaitingLLM")
    #expect(messages[2] == "operationCompleted mode=dictation")
    #expect(messages[3].contains("llmUnauthorized"))
    #expect(messages[4] == "operationCancelled mode=command")
  }

  @Test
  func failedPhaseUsesOnlyTheErrorCaseIdentifier() {
    let message = RedactedLogger.message(
      for: .phaseChanged(
        mode: .command,
        phase: .failed(.credentialMalformed)
      )
    )

    #expect(message == "phaseChanged mode=command phase=failed(credentialMalformed)")
  }
}
