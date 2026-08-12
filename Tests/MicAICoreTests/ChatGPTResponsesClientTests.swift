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
  func reassemblesSSEEventsFragmentedAcrossEveryByteBoundary() async throws {
    let body = deltaFrame("HEL") + deltaFrame("LO") + completedFrame()
    let chunks = Data(body.utf8).map { Data([$0]) }
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
      transport: FakeTransport([
        ResponsesHTTPResponse(statusCode: 200, bodyChunks: chunks)
      ])
    )

    #expect(try await client.transform(anyRequest()) == "HELLO")
  }

  @Test
  func cancellationStopsMidStreamPromptly() async {
    let body = CancellableResponseBody(initialChunk: Data(deltaFrame("PARTIAL").utf8))
    let transport = FakeTransport([
      ResponsesHTTPResponse(statusCode: 200, body: body.stream)
    ])
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
      transport: transport
    )
    let transform = Task {
      try await client.transform(anyRequest())
    }

    while await transport.requests.isEmpty {
      await Task.yield()
    }
    for _ in 0..<10 {
      await Task.yield()
    }
    let startedAt = ContinuousClock.now
    transform.cancel()

    do {
      _ = try await transform.value
      Issue.record("Expected cancellation")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }
    #expect(ContinuousClock.now - startedAt < .seconds(1))
    #expect(body.wasCancelled)
  }

  @Test
  func cancellationBeforeResponseHeadersMapsToCancelled() async {
    let statuses = ProviderStatusCollector()
    let request = anyRequest()
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
      transport: FailingTransport(error: URLError(.cancelled)),
      scopedStatusHandler: statuses.append
    )

    await expectFailure(from: client, request: request, is: .cancelled)
    #expect(
      statuses.values == [
        ProviderStatusEvent(requestID: request.sessionID, status: .failed(.cancelled))
      ])
  }

  @Test
  func transportTimeoutMapsToServerFailure() async {
    let timeout = URLError(.timedOut)
    let transport = FakeTransport([
      ResponsesHTTPResponse(
        statusCode: 200,
        body: AsyncThrowingStream<Data, any Error> { continuation in
          continuation.finish(throwing: timeout)
        }
      )
    ])
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
      transport: transport,
      requestTimeout: 0.25
    )

    await expectFailure(from: client, request: anyRequest(), is: .llmServerFailure)
    #expect(await transport.requests.first?.timeoutInterval == 0.25)
  }

  @Test
  func earlyEOFDiscardsPartialOutput() async {
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
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
  func completesAfterMultipleStreamedEvents() async throws {
    let chunks = [
      Data(deltaFrame("ONE ").utf8),
      Data(deltaFrame("TWO").utf8),
      Data(completedFrame().utf8),
    ]
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
      transport: FakeTransport([
        ResponsesHTTPResponse(statusCode: 200, bodyChunks: chunks)
      ])
    )

    #expect(try await client.transform(anyRequest()) == "ONE TWO")
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
  func providerStatusReportsCredentialRetryAndRecovery() async throws {
    let statuses = ProviderStatusCollector()
    let request = anyRequest()
    let client = ChatGPTResponsesClient(
      credentialLoader: CountingCredentialLoader(),
      transport: FakeTransport([
        ResponsesHTTPResponse(statusCode: 401, bodyChunks: []),
        okResponse(deltas: ["OK"]),
      ]),
      scopedStatusHandler: statuses.append
    )

    _ = try await client.transform(request)

    #expect(
      statuses.values == [
        ProviderStatusEvent(requestID: request.sessionID, status: .retryingCredential),
        ProviderStatusEvent(requestID: request.sessionID, status: .readyToAttempt),
      ])
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

private struct FailingTransport: ResponsesHTTPTransport {
  let error: URLError

  func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse {
    throw error
  }
}

private final class CancellableResponseBody: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
  let stream: AsyncThrowingStream<Data, any Error>

  init(initialChunk: Data) {
    var capturedContinuation: AsyncThrowingStream<Data, any Error>.Continuation?
    stream = AsyncThrowingStream { continuation in
      capturedContinuation = continuation
    }
    continuation = capturedContinuation
    continuation?.onTermination = { [weak self] termination in
      guard case .cancelled = termination else {
        return
      }
      self?.lock.withLock {
        self?.cancelled = true
      }
    }
    continuation?.yield(initialChunk)
  }

  var wasCancelled: Bool {
    lock.withLock { cancelled }
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

private struct ProviderStatusEvent: Sendable, Equatable {
  let requestID: UUID
  let status: ProviderStatus
}

private final class ProviderStatusCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValues: [ProviderStatusEvent] = []

  var values: [ProviderStatusEvent] {
    lock.withLock { storedValues }
  }

  func append(requestID: UUID, status: ProviderStatus) {
    lock.withLock {
      storedValues.append(ProviderStatusEvent(requestID: requestID, status: status))
    }
  }
}
