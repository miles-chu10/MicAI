import Foundation

public struct OpenAITranscriptionHTTPResponse: Sendable, Equatable {
  public let statusCode: Int
  public let body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }
}

public protocol OpenAITranscriptionHTTPTransport: Sendable {
  func perform(_ request: URLRequest) async throws -> OpenAITranscriptionHTTPResponse
}

public struct URLSessionOpenAITranscriptionTransport:
  OpenAITranscriptionHTTPTransport, Sendable
{
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func perform(
    _ request: URLRequest
  ) async throws -> OpenAITranscriptionHTTPResponse {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw MicAIError.transcriptionServerFailure
    }
    return OpenAITranscriptionHTTPResponse(
      statusCode: response.statusCode,
      body: data
    )
  }
}

public protocol OpenAITranscribing: Sendable {
  func transcribe(
    samples: [Float],
    sampleRate: Int,
    model: String
  ) async throws -> Transcript
}

public actor OpenAITranscriptionClient: OpenAITranscribing {
  public static let endpoint = URL(
    string: "https://api.openai.com/v1/audio/transcriptions"
  )!
  public static let defaultRequestTimeout: TimeInterval = 60

  private struct ResponsePayload: Decodable {
    let text: String
  }

  private let apiKeyProvider: any OpenAIAPIKeyProviding
  private let transport: any OpenAITranscriptionHTTPTransport
  private let requestTimeout: TimeInterval
  private let fixedBoundary: String?

  public init(
    apiKeyProvider: any OpenAIAPIKeyProviding,
    transport: any OpenAITranscriptionHTTPTransport = URLSessionOpenAITranscriptionTransport(),
    requestTimeout: TimeInterval = OpenAITranscriptionClient.defaultRequestTimeout,
    boundary: String? = nil
  ) {
    self.apiKeyProvider = apiKeyProvider
    self.transport = transport
    self.requestTimeout = requestTimeout
    fixedBoundary = boundary
  }

  public func transcribe(
    samples: [Float],
    sampleRate: Int,
    model: String
  ) async throws -> Transcript {
    do {
      try Task.checkCancellation()
      let key = try await apiKeyProvider.apiKey()?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard let key, !key.isEmpty else {
        throw MicAIError.transcriptionNotConfigured
      }
      try Task.checkCancellation()

      let wav = try PCM16WAVEncoder.encode(
        samples: samples,
        sampleRate: sampleRate
      )
      let boundary = fixedBoundary ?? "MicAI-\(UUID().uuidString)"
      let request = makeRequest(
        apiKey: key,
        model: model,
        wav: wav,
        boundary: boundary
      )
      let startedAt = ContinuousClock.now
      let response = try await transport.perform(request)
      try Task.checkCancellation()
      let payload = try parse(response)
      let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        throw MicAIError.transcriptionIncomplete
      }
      return Transcript(
        text: text,
        audioDuration: Double(samples.count) / Double(sampleRate),
        processingDuration: startedAt.duration(to: .now).timeInterval,
        confidence: 0
      )
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch let error as URLError where error.code == .cancelled {
      throw MicAIError.cancelled
    } catch let error as URLError where error.code == .timedOut {
      throw MicAIError.transcriptionTimedOut
    } catch let error as MicAIError {
      throw error
    } catch {
      if Task.isCancelled {
        throw MicAIError.cancelled
      }
      throw MicAIError.transcriptionServerFailure
    }
  }

  private func makeRequest(
    apiKey: String,
    model: String,
    wav: Data,
    boundary: String
  ) -> URLRequest {
    var body = Data()
    append("--\(boundary)\r\n", to: &body)
    append("Content-Disposition: form-data; name=\"model\"\r\n\r\n", to: &body)
    append("\(model)\r\n", to: &body)
    append("--\(boundary)\r\n", to: &body)
    append(
      "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n",
      to: &body
    )
    append("Content-Type: audio/wav\r\n\r\n", to: &body)
    body.append(wav)
    append("\r\n--\(boundary)--\r\n", to: &body)

    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.httpBody = body
    request.timeoutInterval = requestTimeout
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    return request
  }

  private func parse(
    _ response: OpenAITranscriptionHTTPResponse
  ) throws -> ResponsePayload {
    switch response.statusCode {
    case 200..<300:
      do {
        return try JSONDecoder().decode(ResponsePayload.self, from: response.body)
      } catch {
        throw MicAIError.transcriptionIncomplete
      }
    case 401:
      throw MicAIError.transcriptionUnauthorized
    case 403:
      throw MicAIError.transcriptionForbidden
    case 429:
      throw MicAIError.transcriptionRateLimited
    default:
      throw MicAIError.transcriptionServerFailure
    }
  }

  private func append(_ string: String, to data: inout Data) {
    data.append(contentsOf: string.utf8)
  }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let components = self.components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
  }
}
