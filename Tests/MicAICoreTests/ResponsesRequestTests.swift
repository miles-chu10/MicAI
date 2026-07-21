import Foundation
import MicAICore
import Testing

@Suite
struct ResponsesRequestTests {
  @Test
  func encodesCanonicalCodexRequestShape() throws {
    let sessionID = UUID()
    let object = try encodedObject(
      LLMRequest(
        instruction: "make this uppercase",
        selectedText: "hello",
        model: "gpt-5-codex",
        sessionID: sessionID
      )
    )

    #expect(object["model"] as? String == "gpt-5-codex")
    #expect(object["instructions"] as? String == ResponsesRequest.instructions)
    #expect((object["tools"] as? [Any])?.isEmpty == true)
    #expect(object["tool_choice"] as? String == "auto")
    #expect(object["parallel_tool_calls"] as? Bool == false)
    #expect(object["reasoning"] is NSNull)
    #expect(object["store"] as? Bool == false)
    #expect(object["stream"] as? Bool == true)
    #expect((object["include"] as? [Any])?.isEmpty == true)
    #expect(object["prompt_cache_key"] as? String == sessionID.uuidString)

    let metadata = try #require(object["client_metadata"] as? [String: Any])
    #expect(metadata["session_id"] as? String == sessionID.uuidString)
    #expect(metadata["thread_id"] as? String == sessionID.uuidString)
  }

  @Test
  func wrapsInstructionAndSelectionAsSeparateJSONFields() throws {
    let object = try encodedObject(
      LLMRequest(
        instruction: "make this uppercase",
        selectedText: "hello",
        model: "gpt-5-codex"
      )
    )
    let payload = try payloadObject(from: object)

    #expect(payload["instruction"] as? String == "make this uppercase")
    #expect(payload["selected_text"] as? String == "hello")
  }

  @Test
  func absentSelectionSerializesAsJSONNull() throws {
    let object = try encodedObject(
      LLMRequest(instruction: "write a haiku", selectedText: nil, model: "gpt-5-codex")
    )
    let payload = try payloadObject(from: object)

    #expect(payload["instruction"] as? String == "write a haiku")
    #expect(payload["selected_text"] is NSNull)
  }

  @Test
  func userTextIsJSONEncodedNotInterpolated() throws {
    let instruction = "He said \"hi\"\nand \\ escaped {\"json\":true}"
    let selection = "line1\nline2 with \"quotes\""
    let object = try encodedObject(
      LLMRequest(instruction: instruction, selectedText: selection, model: "gpt-5-codex")
    )
    let payload = try payloadObject(from: object)

    #expect(payload["instruction"] as? String == instruction)
    #expect(payload["selected_text"] as? String == selection)
  }

  // Decodes the outer request body into a dictionary for structural assertions.
  private func encodedObject(_ request: LLMRequest) throws -> [String: Any] {
    let data = try ResponsesRequest(request: request).encodedData()
    return try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
  }

  // Extracts and re-parses the user input_text, which is itself a JSON string.
  private func payloadObject(from object: [String: Any]) throws -> [String: Any] {
    let input = try #require(object["input"] as? [[String: Any]])
    let content = try #require(input.first?["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "input_text")
    let text = try #require(content.first?["text"] as? String)
    let payloadData = try #require(text.data(using: .utf8))
    return try #require(
      try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
    )
  }
}
