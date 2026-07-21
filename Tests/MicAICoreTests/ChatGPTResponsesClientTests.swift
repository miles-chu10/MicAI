import Foundation
import MicAICore
import Testing

@Suite
struct ChatGPTResponsesClientTests {
  @Test
  func successReturnsAccumulatedOutputAndSendsVerifiedHeaders() async throws {
    let request = LLMRequest(
      instruction: "make this uppercase",
      selectedText: "hello",
      model: "gpt-5-codex"
    )
    let loader = CountingCredentialLoader()
    let transport = FakeTransport([okResponse(deltas: ["HEL", "LO"])])
    let client = ChatGPTResponsesClient(credentialLoader: loader, transport: transport)

    let output = try await client.transform(request)

    #expect(output == "HELLO")
    #expect(loader.loadCount == 1)

    let sent = try #require(await transport.requests.first)
    #expect(sent.url == ChatGPTResponsesClient.endpoint)
    #expect(sent.httpMethod == "POST")
    #expect(header(sent, "Authorization") == "Bearer fake-access-token")
    #expect(header(sent, "ChatGPT-Account-ID") == "fake-account-id")
    #expect(header(sent, "originator") == "codex_cli_rs")
    #expect(header(sent, "Accept") == "text/event-stream")
    #expect(header(sent, "Content-Type") == "application/json")
    #expect(header(sent, "version") == "0.144.6")

    let session = request.sessionID.uuidString
    #expect(header(sent, "session-id") == session)
    #expect(header(sent, "thread-id") == session)
    #expect(header(sent, "x-client-request-id") == session)
  }

  @Test
  func streamsAcrossMultipleBodyChunks() async throws {
    let loader = CountingCredentialLoader()
    let transport = FakeTransport([
      ResponsesHTTPResponse(
        statusCode: 200,
        bodyChunks: [
          Data(deltaFrame("HEL").utf8),
          Data((deltaFrame("LO") + completedFrame()).utf8),
        ]
      )
    ])
    let client = ChatGPTResponsesClient(credentialLoader: loader, transport: transport)

    #expect(try await client.transform(anyRequest()) == "HELLO")
  }

  @Test
  func unauthorizedTriggersExactlyOneReloadAndRetry() async throws {
    let loader = CountingCredentialLoader()
    let transport = FakeTransport([
      ResponsesHTTPResponse(statusCode: 401, bodyChunks: []),
      okResponse(deltas: ["OK"]),
    ])
    let client = ChatGPTResponsesClient(credentialLoader: loader, transport: transport)

    let output = try await client.transform(anyRequest())

    #expect(output == "OK")
    #expect(loader.loadCount == 2)
    #expect(await transport.requests.count == 2)
  }

  @Test
  func secondUnauthorizedReportsUnauthorizedWithoutFurtherRetry() async throws {
    let loader = CountingCredentialLoader()
    let transport = FakeTransport([
      ResponsesHTTPResponse(statusCode: 401, bodyChunks: []),
      ResponsesHTTPResponse(statusCode: 401, bodyChunks: []),
    ])
    let client = ChatGPTResponsesClient(credentialLoader: loader, transport: transport)

    await expectFailure(from: client, request: anyRequest(), is: .llmUnauthorized)
    #expect(loader.loadCount == 2)
    #expect(await transport.requests.count == 2)
  }

  @Test
  func forbiddenRateLimitedAndServerFailuresMapToTypedErrors() async throws {
    await expectStatus(403, mapsTo: .llmForbidden)
    await expectStatus(429, mapsTo: .llmRateLimited)
    await expectStatus(500, mapsTo: .llmServerFailure)
  }

  @Test
  func missingCredentialFailsBeforeAnyRequest() async throws {
    let loader = CountingCredentialLoader(error: .credentialMissing)
    let transport = FakeTransport([])
    let client = ChatGPTResponsesClient(credentialLoader: loader, transport: transport)

    await expectFailure(from: client, request: anyRequest(), is: .credentialMissing)
    #expect(await transport.requests.isEmpty)
  }

  private func expectStatus(_ statusCode: Int, mapsTo expected: MicAIError) async {
    let transport = FakeTransport([
      ResponsesHTTPResponse(statusCode: statusCode, bodyChunks: [])
    ])
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
      transport: transport
    )
    await expectFailure(from: client, request: anyRequest(), is: expected)
  }

  private func expectFailure(
    from client: ChatGPTResponsesClient,
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
    LLMRequest(instruction: "do it", selectedText: nil, model: "gpt-5-codex")
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

private final class CountingCredentialLoader: CredentialLoading, @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  private let credential: ChatGPTCredential
  private let error: MicAIError?

  init(
    credential: ChatGPTCredential = ChatGPTCredential(
      accessToken: "fake-access-token",
      accountID: "fake-account-id"
    ),
    error: MicAIError? = nil
  ) {
    self.credential = credential
    self.error = error
  }

  var loadCount: Int {
    lock.withLock { count }
  }

  func load() throws -> ChatGPTCredential {
    try lock.withLock {
      count += 1
      if let error {
        throw error
      }
      return credential
    }
  }
}
