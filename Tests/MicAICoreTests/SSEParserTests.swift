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
