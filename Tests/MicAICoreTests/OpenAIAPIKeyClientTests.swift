import Foundation
import MicAICore
import Testing

@Suite
struct OpenAIAPIKeyClientTests {
  @Test
  func successReturnsAccumulatedOutputAndSendsAPIKeyHeaders() async throws {
    let transport = FakeTransport([okResponse(deltas: ["HEL", "LO"])])
    let client = OpenAIAPIKeyClient(
      environment: ["OPENAI_API_KEY": "fake-api-key"],
      transport: transport
    )

    let output = try await client.transform(anyRequest())

    #expect(output == "HELLO")
    let sent = try #require(await transport.requests.first)
    #expect(sent.url == OpenAIAPIKeyClient.endpoint)
    #expect(sent.httpMethod == "POST")
    #expect(header(sent, "Authorization") == "Bearer fake-api-key")
    #expect(header(sent, "Accept") == "text/event-stream")
    #expect(header(sent, "Content-Type") == "application/json")
    #expect(header(sent, "ChatGPT-Account-ID") == nil)
    #expect(header(sent, "originator") == nil)
  }

  @Test
  func missingAPIKeyFailsBeforeAnyRequest() async {
    let transport = FakeTransport([])
    let client = OpenAIAPIKeyClient(environment: [:], transport: transport)

    await expectFailure(from: client, request: anyRequest(), is: .credentialMissing)
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func blankAPIKeyIsTreatedAsMissing() async {
    let transport = FakeTransport([])
    let client = OpenAIAPIKeyClient(
      environment: ["OPENAI_API_KEY": "  \n "],
      transport: transport
    )

    await expectFailure(from: client, request: anyRequest(), is: .credentialMissing)
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func earlyEOFDiscardsPartialOutput() async {
    let client = OpenAIAPIKeyClient(
      environment: ["OPENAI_API_KEY": "fake-api-key"],
      transport: FakeTransport([
        ResponsesHTTPResponse(
          statusCode: 200,
          bodyChunks: [Data(deltaFrame("PARTIAL").utf8)]
        )
      ])
    )

    await expectFailure(from: client, request: anyRequest(), is: .llmIncomplete)
  }

  @Test
  func statusFailuresMapToTypedErrorsWithoutRetry() async {
    await expectStatus(401, mapsTo: .llmUnauthorized)
    await expectStatus(403, mapsTo: .llmForbidden)
    await expectStatus(429, mapsTo: .llmRateLimited)
    await expectStatus(500, mapsTo: .llmServerFailure)
  }

  @Test
  func cancellationBeforeResponseHeadersMapsToCancelled() async {
    let client = OpenAIAPIKeyClient(
      environment: ["OPENAI_API_KEY": "fake-api-key"],
      transport: FailingTransport(error: URLError(.cancelled))
    )

    await expectFailure(from: client, request: anyRequest(), is: .cancelled)
  }

  private func expectStatus(_ statusCode: Int, mapsTo expected: MicAIError) async {
    let transport = FakeTransport([
      ResponsesHTTPResponse(statusCode: statusCode, bodyChunks: [])
    ])
    let client = OpenAIAPIKeyClient(
      environment: ["OPENAI_API_KEY": "fake-api-key"],
      transport: transport
    )
    await expectFailure(from: client, request: anyRequest(), is: expected)
    #expect(await transport.requests.count == 1)
  }

  private func expectFailure(
    from client: OpenAIAPIKeyClient,
    request: LLMRequest,
    is expected: MicAIError
  ) async {
    do {
      _ = try await client.transform(request)
      Issue.record("Expected \(expected)")
    } catch {
      #expect(error as? MicAIError == expected)
    }
  }

  private func anyRequest() -> LLMRequest {
    LLMRequest(instruction: "do it", selectedText: nil, model: "gpt-5.4")
  }

  private func okResponse(deltas: [String]) -> ResponsesHTTPResponse {
    let body = deltas.map(deltaFrame).joined() + completedFrame()
    return ResponsesHTTPResponse(statusCode: 200, bodyChunks: [Data(body.utf8)])
  }

  private func deltaFrame(_ delta: String) -> String {
    "data: {\"type\":\"response.output_text.delta\",\"delta\":\"\(delta)\"}\n\n"
  }

  private func completedFrame() -> String {
    "data: {\"type\":\"response.completed\"}\n\n"
  }

  private func header(_ request: URLRequest, _ name: String) -> String? {
    request.value(forHTTPHeaderField: name)
  }
}

private struct FailingTransport: ResponsesHTTPTransport {
  let error: URLError

  func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse {
    throw error
  }
}

private actor FakeTransport: ResponsesHTTPTransport {
  private var queue: [ResponsesHTTPResponse]
  private(set) var requests: [URLRequest] = []

  init(_ queue: [ResponsesHTTPResponse]) {
    self.queue = queue
  }

  func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse {
    requests.append(request)
    return queue.removeFirst()
  }
}
