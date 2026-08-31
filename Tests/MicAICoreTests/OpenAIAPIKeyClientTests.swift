import Foundation
import MicAICore
import Testing

@Suite
struct OpenAIAPIKeyClientTests {
  @Test
  func transformUsesPublicResponsesRequestContract() async throws {
    let sessionID = UUID()
    let request = LLMRequest(
      instruction: "make this uppercase",
      selectedText: "hello",
      model: "gpt-5",
      sessionID: sessionID
    )
    let transport = OpenAIRecordingTransport(
      response: ResponsesHTTPResponse(
        statusCode: 200,
        bodyChunks: [
          Data(
            ("data: {\"type\":\"response.output_text.delta\",\"delta\":\"HELLO\"}\n\n"
              + "data: {\"type\":\"response.completed\"}\n\n").utf8
          )
        ]
      )
    )
    let client = OpenAIAPIKeyClient(
      environment: ["OPENAI_API_KEY": "fake-key"],
      transport: transport
    )

    #expect(try await client.transform(request) == "HELLO")

    let sent = try #require(await transport.requests.first)
    #expect(sent.url == OpenAIAPIKeyClient.endpoint)
    #expect(sent.httpMethod == "POST")
    #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key")
    #expect(sent.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try #require(sent.httpBody)
    let object = try #require(
      try JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    #expect(object["model"] as? String == "gpt-5")
    #expect(object["prompt_cache_key"] as? String == sessionID.uuidString)
    #expect(object["client_metadata"] == nil)
  }
}

private actor OpenAIRecordingTransport: ResponsesHTTPTransport {
  let response: ResponsesHTTPResponse
  private(set) var requests: [URLRequest] = []

  init(response: ResponsesHTTPResponse) {
    self.response = response
  }

  func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse {
    requests.append(request)
    return response
  }
}
