import Foundation

public struct ResponsesHTTPResponse: Sendable {
  public let statusCode: Int
  public let body: AsyncThrowingStream<Data, any Error>

  public init(statusCode: Int, bodyChunks: [Data]) {
    self.init(
      statusCode: statusCode,
      body: AsyncThrowingStream { continuation in
        for chunk in bodyChunks {
          continuation.yield(chunk)
        }
        continuation.finish()
      }
    )
  }

  public init(
    statusCode: Int,
    body: AsyncThrowingStream<Data, any Error>
  ) {
    self.statusCode = statusCode
    self.body = body
  }
}

public protocol ResponsesHTTPTransport: Sendable {
  func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse
}

public actor ChatGPTResponsesClient: LLMTransforming {
  public static let endpoint = URL(
    string: "https://chatgpt.com/backend-api/codex/responses"
  )!
  public static let defaultRequestTimeout: TimeInterval = 60

  private let credentialLoader: any CredentialLoading
  private let transport: any ResponsesHTTPTransport
  private let requestTimeout: TimeInterval
  private let statusHandler: @Sendable (ProviderStatus) -> Void
  private var cachedCredential: ChatGPTCredential?

  public init(
    credentialLoader: any CredentialLoading = CodexAuthFileLoader(),
    transport: any ResponsesHTTPTransport = URLSessionResponsesTransport(),
    requestTimeout: TimeInterval = ChatGPTResponsesClient.defaultRequestTimeout,
    statusHandler: @escaping @Sendable (ProviderStatus) -> Void = { _ in }
  ) {
    self.credentialLoader = credentialLoader
    self.transport = transport
    self.requestTimeout = requestTimeout
    self.statusHandler = statusHandler
  }

  public func transform(_ request: LLMRequest) async throws -> String {
    do {
      try Task.checkCancellation()
      let credential = try currentCredential()
      let firstResponse = try await perform(request, credential: credential)

      guard firstResponse.statusCode == 401 else {
        let output = try await parse(firstResponse)
        statusHandler(.readyToAttempt)
        return output
      }

      statusHandler(.retryingCredential)
      cachedCredential = nil
      let reloadedCredential = try loadCredential()
      let retryResponse = try await perform(request, credential: reloadedCredential)
      guard retryResponse.statusCode != 401 else {
        throw MicAIError.llmUnauthorized
      }
      let output = try await parse(retryResponse)
      statusHandler(.readyToAttempt)
      return output
    } catch is CancellationError {
      let error = MicAIError.cancelled
      statusHandler(.failed(error))
      throw error
    } catch let error as MicAIError {
      statusHandler(.failed(error))
      throw error
    }
  }

  private func currentCredential() throws -> ChatGPTCredential {
    if let cachedCredential {
      return cachedCredential
    }
    return try loadCredential()
  }

  private func loadCredential() throws -> ChatGPTCredential {
    let credential = try credentialLoader.load()
    cachedCredential = credential
    return credential
  }

  private func perform(
    _ request: LLMRequest,
    credential: ChatGPTCredential
  ) async throws -> ResponsesHTTPResponse {
    let urlRequest = try makeURLRequest(request, credential: credential)
    do {
      return try await transport.perform(urlRequest)
    } catch is CancellationError {
      throw MicAIError.cancelled
    } catch let error as URLError where error.code == .cancelled {
      throw MicAIError.cancelled
    } catch let error as MicAIError {
      throw error
    } catch {
      throw MicAIError.llmServerFailure
    }
  }

  private func makeURLRequest(
    _ request: LLMRequest,
    credential: ChatGPTCredential
  ) throws -> URLRequest {
    var urlRequest = URLRequest(url: Self.endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = try ResponsesRequest(request: request).encodedData(
      for: .chatGPTCodex
    )
    urlRequest.timeoutInterval = requestTimeout
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    urlRequest.setValue(
      "Bearer \(credential.accessToken)",
      forHTTPHeaderField: "Authorization"
    )
    urlRequest.setValue(
      credential.accountID,
      forHTTPHeaderField: "ChatGPT-Account-ID"
    )
    urlRequest.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
    urlRequest.setValue(request.sessionID.uuidString, forHTTPHeaderField: "session-id")
    urlRequest.setValue(request.sessionID.uuidString, forHTTPHeaderField: "thread-id")
    urlRequest.setValue(
      request.sessionID.uuidString,
      forHTTPHeaderField: "x-client-request-id"
    )
    urlRequest.setValue("0.144.6", forHTTPHeaderField: "version")
    return urlRequest
  }

  private func parse(_ response: ResponsesHTTPResponse) async throws -> String {
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
        throw CancellationError()
      } catch let error as URLError
        where error.code == .cancelled && Task.isCancelled
      {
        throw CancellationError()
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
