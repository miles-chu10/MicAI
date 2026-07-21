import Foundation

public actor OpenAIAPIKeyClient: LLMTransforming {
  public static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

  private let apiKey: String?
  private let transport: any ResponsesHTTPTransport

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    transport: any ResponsesHTTPTransport = URLSessionResponsesTransport()
  ) {
    let value = environment["OPENAI_API_KEY"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    apiKey = value?.isEmpty == false ? value : nil
    self.transport = transport
  }

  public func transform(_ request: LLMRequest) async throws -> String {
    guard let apiKey else {
      throw MicAIError.credentialMissing
    }

    var urlRequest = URLRequest(url: Self.endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = try ResponsesRequest(request: request).encodedData()
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let response: ResponsesHTTPResponse
    do {
      response = try await transport.perform(urlRequest)
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch let error as MicAIError {
      throw error
    } catch {
      throw MicAIError.llmServerFailure
    }

    switch response.statusCode {
    case 200..<300:
      var parser = SSEParser()
      for chunk in response.bodyChunks {
        try Task.checkCancellation()
        try parser.append(chunk)
      }
      return try parser.finish()
    case 401:
      throw MicAIError.llmUnauthorized
    case 403:
      throw MicAIError.llmForbidden
    case 429:
      throw MicAIError.llmRateLimited
    default:
      throw MicAIError.llmServerFailure
    }
  }
}
