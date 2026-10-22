import Foundation
import MicAICore
import Testing

struct CodexJSONParserTests {
  @Test
  func byteChunksKeepOnlyTheLastAssistantMessageAndNeverExecuteToolEvents() throws {
    let body = """
      {"type":"thread.started","thread_id":"synthetic"}
      {"type":"item.completed","item":{"type":"reasoning","text":"reasoning"}}
      {"type":"item.completed","item":{"type":"command_execution","command":"exit 9","text":"tool"}}
      {"type":"item.completed","item":{"type":"agent_message","text":"earlier"}}
      {"type":"item.completed","item":{"type":"agent_message","phase":"commentary","text":"progress"}}
      {"type":"item.completed","item":{"type":"agent_message","phase":"final_answer","text":"final 🐈\\n"}}
      {"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":1024,"output_tokens":5}}
      """
    var parser = CodexJSONParser()
    for byte in body.utf8 { try parser.append(Data([byte])) }

    #expect(try parser.finish() == "final 🐈\n")
    #expect(parser.usage == LLMUsage(inputTokens: 1200, cachedInputTokens: 1024, outputTokens: 5))
  }

  @Test(arguments: [
    "null", "{}", "false", #"{"input_tokens":"bad","cached_input_tokens":-1,"output_tokens":null}"#,
  ])
  func absentOrMalformedUsageRemainsUnknownWithoutChangingText(_ usage: String) throws {
    var parser = CodexJSONParser()
    try parser.append(
      Data((message + "\n{\"type\":\"turn.completed\",\"usage\":\(usage)}\r\n").utf8))

    #expect(try parser.finish() == "OK")
    #expect(parser.usage == LLMUsage())
  }

  @Test
  func malformedUsageFieldsDoNotDiscardOtherValidCounts() throws {
    var parser = CodexJSONParser()
    try parser.append(
      Data(
        (message + "\n"
          + #"{"type":"turn.completed","usage":{"input_tokens":20,"cached_input_tokens":false,"output_tokens":2}}"#)
          .utf8))
    #expect(try parser.finish() == "OK")
    #expect(parser.usage == LLMUsage(inputTokens: 20, outputTokens: 2))
  }

  @Test(arguments: [
    #"{"type":"error","message":"401 Unauthorized"}"#,
    #"{"type":"turn.failed","error":{"message":"not logged in; run codex login"}}"#,
  ])
  func unauthorizedJSONReportsUsefulFailure(_ event: String) {
    var parser = CodexJSONParser()
    #expect(throws: MicAIError.llmUnauthorized) {
      try parser.append(Data(event.utf8))
      _ = try parser.finish()
    }
  }

  @Test
  func progressWithoutFinalAnswerDoesNotBecomeOutput() throws {
    var parser = CodexJSONParser()
    let body = """
      {"type":"item.completed","item":{"type":"agent_message","phase":"commentary","text":"progress"}}
      {"type":"turn.completed"}
      """
    try parser.append(Data(body.utf8))
    #expect(throws: MicAIError.llmIncomplete) { try parser.finish() }
  }

  @Test
  func recoveredErrorDoesNotDiscardACompletedFinalAnswer() throws {
    var parser = CodexJSONParser()
    let body =
      #"{"type":"error","message":"reconnecting"}"#
      + "\n" + message + "\n" + #"{"type":"turn.completed"}"#
    try parser.append(Data(body.utf8))
    #expect(try parser.finish() == "OK")
  }

  @Test
  func duplicateCompletionCannotCountUsageTwice() {
    var parser = CodexJSONParser()
    let completion =
      #"{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":80}}"#
    #expect(throws: MicAIError.llmIncomplete) {
      try parser.append(Data((message + "\n" + completion + "\n" + completion + "\n").utf8))
    }
  }

  @Test
  func toolCommandNeverCreatesAFile() throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent(
      "micai-no-tool-\(UUID().uuidString)")
    let toolEvent = try JSONSerialization.data(withJSONObject: [
      "type": "item.completed",
      "item": ["type": "command_execution", "command": "touch \(marker.path)"],
    ])
    var parser = CodexJSONParser()
    try parser.append(
      toolEvent + Data(("\n" + message + "\n" + #"{"type":"turn.completed"}"#).utf8))
    #expect(try parser.finish() == "OK")
    #expect(!FileManager.default.fileExists(atPath: marker.path))
  }

  private let message = #"{"type":"item.completed","item":{"type":"agent_message","text":"OK"}}"#
}
