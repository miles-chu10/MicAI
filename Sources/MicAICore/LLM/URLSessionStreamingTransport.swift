import Foundation

public struct URLSessionResponsesTransport: ResponsesHTTPTransport, Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func perform(_ request: URLRequest) async throws -> ResponsesHTTPResponse {
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw MicAIError.llmServerFailure
    }

    let body = AsyncThrowingStream<Data, any Error> { continuation in
      let producer = Task {
        do {
          var chunk = Data()
          chunk.reserveCapacity(4_096)

          for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if byte == 0x0A || chunk.count == 4_096 {
              continuation.yield(chunk)
              chunk.removeAll(keepingCapacity: true)
            }
          }

          if !chunk.isEmpty {
            continuation.yield(chunk)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        producer.cancel()
      }
    }

    return ResponsesHTTPResponse(
      statusCode: response.statusCode,
      body: body
    )
  }
}
