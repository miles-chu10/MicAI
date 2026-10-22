import Foundation
import MicAICore
import Testing

@Suite
struct SSEParserTests {
  @Test
  func accumulatesMultipleDeltasUntilCompleted() throws {
    var parser = SSEParser()
    try parser.append(Data(stream(deltas: ["HEL", "LO"], completed: true).utf8))

    #expect(try parser.finish() == "HELLO")
  }

  @Test
  func completionRetainsOptionalUsageAndModelAcrossByteChunks() throws {
    let body = """
      data: {"type":"response.output_text.delta","delta":"OK"}

      data: {"type":"response.completed","response":{"model":"synthetic-text-model","usage":{"input_tokens":1200,"output_tokens":5,"input_tokens_details":{"cached_tokens":1024,"cache_write_tokens":128}}}}


      """
    var parser = SSEParser()
    for byte in body.utf8 { try parser.append(Data([byte])) }
    #expect(try parser.finish() == "OK")
    #expect(parser.responseModel == "synthetic-text-model")
    #expect(
      parser.usage
        == LLMUsage(
          inputTokens: 1200, cachedInputTokens: 1024, cacheWriteTokens: 128, outputTokens: 5))
  }

  @Test(arguments: [
    "null", "{}", "false",
    #"{"input_tokens":-1,"output_tokens":"bad","input_tokens_details":{"cached_tokens":false}}"#,
  ])
  func missingOrMalformedUsageDoesNotChangeOutput(_ usage: String) throws {
    var parser = SSEParser()
    let body =
      stream(deltas: ["OK"], completed: false)
      + "data: {\"type\":\"response.completed\",\"response\":{\"usage\":\(usage)}}\n\n"
    try parser.append(Data(body.utf8))
    #expect(try parser.finish() == "OK")
    #expect(parser.usage == LLMUsage())
  }

  @Test
  func malformedDetailsKeepValidInputAndOutputAndExplicitZero() throws {
    var parser = SSEParser()
    let body =
      stream(deltas: ["OK"], completed: false)
      + #"data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":0,"input_tokens_details":"bad"}}}"#
      + "\n\n"
    try parser.append(Data(body.utf8))
    #expect(try parser.finish() == "OK")
    #expect(parser.usage == LLMUsage(inputTokens: 10, outputTokens: 0))
  }

  @Test
  func reassemblesFramesSplitAcrossAppends() throws {
    let bytes = Array(stream(deltas: ["HEL", "LO"], completed: true).utf8)
    let split = bytes.count / 3

    var parser = SSEParser()
    try parser.append(Data(bytes[..<split]))
    try parser.append(Data(bytes[split...]))

    #expect(try parser.finish() == "HELLO")
  }

  @Test
  func parsesCarriageReturnFrameBoundaries() throws {
    let crlf =
      "event: response.output_text.delta\r\n"
      + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"HI\"}\r\n\r\n"
      + "data: {\"type\":\"response.completed\"}\r\n\r\n"

    var parser = SSEParser()
    try parser.append(Data(crlf.utf8))

    #expect(try parser.finish() == "HI")
  }

  @Test
  func ignoresUnknownEventTypesAndDoneSentinel() throws {
    let text =
      "data: {\"type\":\"response.created\"}\n\n"
      + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"OK\"}\n\n"
      + "data: [DONE]\n\n"
      + "data: {\"type\":\"response.completed\"}\n\n"

    var parser = SSEParser()
    try parser.append(Data(text.utf8))

    #expect(try parser.finish() == "OK")
  }

  @Test
  func failedEventReportsIncomplete() {
    var parser = SSEParser()
    expectIncomplete {
      try parser.append(Data("data: {\"type\":\"response.failed\"}\n\n".utf8))
    }
  }

  @Test
  func incompleteEventReportsIncomplete() {
    var parser = SSEParser()
    expectIncomplete {
      try parser.append(Data("data: {\"type\":\"response.incomplete\"}\n\n".utf8))
    }
  }

  @Test
  func eofBeforeCompletionReportsIncomplete() throws {
    var parser = SSEParser()
    try parser.append(Data(stream(deltas: ["PARTIAL"], completed: false).utf8))

    expectIncomplete { _ = try parser.finish() }
  }

  @Test
  func completedWithNoOutputReportsIncomplete() throws {
    var parser = SSEParser()
    try parser.append(Data("data: {\"type\":\"response.completed\"}\n\n".utf8))

    expectIncomplete { _ = try parser.finish() }
  }

  private func stream(deltas: [String], completed: Bool) -> String {
    var text = deltas.reduce(into: "") { accumulated, delta in
      accumulated +=
        "event: response.output_text.delta\n"
        + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"\(delta)\"}\n\n"
    }
    if completed {
      text += "data: {\"type\":\"response.completed\"}\n\n"
    }
    return text
  }

  private func expectIncomplete(_ operation: () throws -> Void) {
    do {
      try operation()
      Issue.record("Expected llmIncomplete")
    } catch {
      #expect(error as? MicAIError == .llmIncomplete)
    }
  }
}
