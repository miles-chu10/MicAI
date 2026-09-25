import Foundation

public actor OpenAIAPIKeyClient: LLMTransforming {
  public static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

  private let apiKeyProvider: @Sendable () -> String?
  private let transport: any ResponsesHTTPTransport

  /// Reads the key from `OPENAI_API_KEY`. Useful from a terminal; an app opened
  /// from Finder does not inherit the shell's environment, so the app itself
  /// uses `init(apiKey:transport:)` with the Keychain.
  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    transport: any ResponsesHTTPTransport = URLSessionResponsesTransport()
  ) {
    let value = environment["OPENAI_API_KEY"]
    self.init(apiKey: { value }, transport: transport)
  }

  /// `apiKey` is asked on every request rather than once, so a key saved or
  /// removed in Settings takes effect on the next dictation without a relaunch.
  public init(
    apiKey: @escaping @Sendable () -> String?,
    transport: any ResponsesHTTPTransport = URLSessionResponsesTransport()
  ) {
    apiKeyProvider = apiKey
    self.transport = transport
  }

  public func transform(_ request: LLMRequest) async throws -> String {
    guard
      let apiKey = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    else {
      throw MicAIError.credentialMissing
    }

    var urlRequest = URLRequest(url: Self.endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = try ResponsesRequest(request: request).encodedData()
    urlRequest.timeoutInterval = ChatGPTResponsesClient.defaultRequestTimeout
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let response: ResponsesHTTPResponse
    do {
      response = try await transport.perform(urlRequest)
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch let error as URLError where error.code == .cancelled {
      throw MicAIError.cancelled
    } catch let error as MicAIError {
      throw error
    } catch {
      throw MicAIError.llmServerFailure
    }

    switch response.statusCode {
    case 200..<300:
      var parser = SSEParser()
      do {
        for try await chunk in response.body {
          try Task.checkCancellation()
          try parser.append(chunk)
        }
        try Task.checkCancellation()
        return try parser.finish()
      } catch is CancellationError {
        throw MicAIError.cancelled
      } catch let error as URLError
        where error.code == .cancelled && Task.isCancelled
      {
        throw MicAIError.cancelled
      } catch let error as MicAIError {
        throw error
      } catch {
        throw MicAIError.llmServerFailure
      }
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
