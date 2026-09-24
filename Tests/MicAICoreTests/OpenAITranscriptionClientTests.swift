import Foundation
import MicAICore
import Testing

@Suite
struct OpenAITranscriptionClientTests {
  @Test
  func buildsExactMultipartTranscriptionRequestAndParsesText() async throws {
    let keyProvider = FakeOpenAIAPIKeyProvider(value: "test-key")
    let transport = FakeOpenAITranscriptionTransport(
      result: .success(
        OpenAITranscriptionHTTPResponse(
          statusCode: 200,
          body: Data(#"{"text":"  hello from OpenAI  "}"#.utf8)
        )
      )
    )
    let client = OpenAITranscriptionClient(
      apiKeyProvider: keyProvider,
      transport: transport,
      requestTimeout: 17,
      boundary: "MicAIBoundary"
    )

    let transcript = try await client.transcribe(
      samples: [Float](repeating: 0.25, count: 4_800),
      sampleRate: 16_000,
      model: "gpt-transcribe"
    )
    let request = try #require(await transport.lastRequest)
    let body = try #require(request.httpBody)
    let bodyText = String(decoding: body, as: UTF8.self)

    #expect(request.url == OpenAITranscriptionClient.endpoint)
    #expect(request.httpMethod == "POST")
    #expect(request.timeoutInterval == 17)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type")
        == "multipart/form-data; boundary=MicAIBoundary"
    )
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(
      bodyText.contains(
        "Content-Disposition: form-data; name=\"model\"\r\n\r\ngpt-transcribe\r\n"
      )
    )
    #expect(
      bodyText.contains(
        "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
      )
    )
    #expect(bodyText.contains("Content-Type: audio/wav\r\n\r\nRIFF"))
    #expect(
      body.suffix(Data("\r\n--MicAIBoundary--\r\n".utf8).count)
        == Data("\r\n--MicAIBoundary--\r\n".utf8))
    #expect(transcript.text == "hello from OpenAI")
    #expect(transcript.audioDuration == 0.3)
    #expect(await keyProvider.accessCount == 1)
    #expect(await transport.performCount == 1)
  }

  @Test
  func missingKeyFailsBeforeEncodingOrTransport() async {
    let keyProvider = FakeOpenAIAPIKeyProvider(value: " \n ")
    let transport = FakeOpenAITranscriptionTransport(
      result: .failure(MicAIError.transcriptionServerFailure)
    )
    let client = OpenAITranscriptionClient(
      apiKeyProvider: keyProvider,
      transport: transport
    )

    await expectError(.transcriptionNotConfigured) {
      try await client.transcribe(
        samples: [0],
        sampleRate: 16_000,
        model: "gpt-transcribe"
      )
    }
    #expect(await keyProvider.accessCount == 1)
    #expect(await transport.performCount == 0)
  }

  @Test
  func rejectsMalformedAndEmptySuccessfulResponses() async {
    for body in [Data("not-json".utf8), Data(#"{"text":" \n "}"#.utf8)] {
      let client = OpenAITranscriptionClient(
        apiKeyProvider: FakeOpenAIAPIKeyProvider(value: "key"),
        transport: FakeOpenAITranscriptionTransport(
          result: .success(
            OpenAITranscriptionHTTPResponse(statusCode: 200, body: body)
          )
        )
      )
      await expectError(.transcriptionIncomplete) {
        try await client.transcribe(
          samples: [0],
          sampleRate: 16_000,
          model: "gpt-transcribe"
        )
      }
    }
  }

  @Test
  func mapsAuthenticationRateLimitAndServerResponses() async {
    let cases: [(Int, MicAIError)] = [
      (401, .transcriptionUnauthorized),
      (403, .transcriptionForbidden),
      (429, .transcriptionRateLimited),
      (500, .transcriptionServerFailure),
    ]

    for (statusCode, expected) in cases {
      let client = OpenAITranscriptionClient(
        apiKeyProvider: FakeOpenAIAPIKeyProvider(value: "key"),
        transport: FakeOpenAITranscriptionTransport(
          result: .success(
            OpenAITranscriptionHTTPResponse(
              statusCode: statusCode,
              body: Data()
            )
          )
        )
      )
      await expectError(expected) {
        try await client.transcribe(
          samples: [0],
          sampleRate: 16_000,
          model: "gpt-transcribe"
        )
      }
    }
  }

  @Test
  func mapsTimeoutAndCancellationWithoutRetry() async {
    let timedOut = OpenAITranscriptionClient(
      apiKeyProvider: FakeOpenAIAPIKeyProvider(value: "key"),
      transport: FakeOpenAITranscriptionTransport(
        result: .failure(URLError(.timedOut))
      )
    )
    await expectError(.transcriptionTimedOut) {
      try await timedOut.transcribe(
        samples: [0],
        sampleRate: 16_000,
        model: "gpt-transcribe"
      )
    }

    let cancelled = OpenAITranscriptionClient(
      apiKeyProvider: FakeOpenAIAPIKeyProvider(value: "key"),
      transport: FakeOpenAITranscriptionTransport(
        result: .failure(CancellationError())
      )
    )
    await expectError(.cancelled) {
      try await cancelled.transcribe(
        samples: [0],
        sampleRate: 16_000,
        model: "gpt-transcribe"
      )
    }
  }

  private func expectError(
    _ expected: MicAIError,
    operation: () async throws -> Transcript
  ) async {
    do {
      _ = try await operation()
      Issue.record("Expected \(expected)")
    } catch {
      #expect(error as? MicAIError == expected)
    }
  }
}

private actor FakeOpenAIAPIKeyProvider: OpenAIAPIKeyProviding {
  private let value: String?
  private(set) var accessCount = 0

  init(value: String?) {
    self.value = value
  }

  func apiKey() async throws -> String? {
    accessCount += 1
    return value
  }
}

private actor FakeOpenAITranscriptionTransport: OpenAITranscriptionHTTPTransport {
  private let result: Result<OpenAITranscriptionHTTPResponse, any Error>
  private(set) var lastRequest: URLRequest?
  private(set) var performCount = 0

  init(result: Result<OpenAITranscriptionHTTPResponse, any Error>) {
    self.result = result
  }

  func perform(
    _ request: URLRequest
  ) async throws -> OpenAITranscriptionHTTPResponse {
    performCount += 1
    lastRequest = request
    return try result.get()
  }
}
