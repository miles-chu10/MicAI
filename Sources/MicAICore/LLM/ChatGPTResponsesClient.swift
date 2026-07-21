import Foundation

public struct ResponsesHTTPResponse: Sendable {
  public let statusCode: Int
  public let bodyChunks: [Data]

  public init(statusCode: Int, bodyChunks: [Data]) {
    self.statusCode = statusCode
    self.bodyChunks = bodyChunks
  }
}

public protocol ResponsesHTTPTransport: Sendable {
  func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse
}

public struct URLSessionResponsesTransport: ResponsesHTTPTransport, Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw MicAIError.llmServerFailure
    }
    return ResponsesHTTPResponse(
      statusCode: response.statusCode,
      bodyChunks: [data]
    )
  }
}

public actor ChatGPTResponsesClient: LLMTransforming {
  public static let endpoint = URL(
    string: "https://chatgpt.com/backend-api/codex/responses"
  )!

  private let credentialLoader: any CredentialLoading
  private let transport: any ResponsesHTTPTransport
  private var cachedCredential: ChatGPTCredential?

  public init(
    credentialLoader: any CredentialLoading = CodexAuthFileLoader(),
    transport: any ResponsesHTTPTransport = URLSessionResponsesTransport()
  ) {
    self.credentialLoader = credentialLoader
    self.transport = transport
  }

  public func transform(_ request: LLMRequest) async throws -> String {
    try Task.checkCancellation()
    let credential = try currentCredential()
    let firstResponse = try await perform(request, credential: credential)

    guard firstResponse.statusCode == 401 else {
      return try parse(firstResponse)
    }

    cachedCredential = nil
    let reloadedCredential = try loadCredential()
    let retryResponse = try await perform(request, credential: reloadedCredential)
    guard retryResponse.statusCode != 401 else {
      throw MicAIError.llmUnauthorized
    }
    return try parse(retryResponse)
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
    urlRequest.httpBody = try ResponsesRequest(request: request).encodedData()
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

  private func parse(_ response: ResponsesHTTPResponse) throws -> String {
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
