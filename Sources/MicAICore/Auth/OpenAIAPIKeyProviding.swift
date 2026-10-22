public protocol OpenAIAPIKeyProviding: Sendable {
  func apiKey() async throws -> String?
}

public struct UnavailableOpenAIAPIKeyProvider: OpenAIAPIKeyProviding, Sendable {
  public init() {}

  public func apiKey() async throws -> String? {
    nil
  }
}
