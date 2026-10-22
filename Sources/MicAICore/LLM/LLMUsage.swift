import Foundation

/// Content-free counts reported by a completed provider response. Missing or
/// malformed fields stay unknown; cache reads and writes are subsets of input.
public struct LLMUsage: Sendable, Equatable, Decodable {
  public let inputTokens: Int?
  public let cachedInputTokens: Int?
  public let cacheWriteTokens: Int?
  public let outputTokens: Int?

  public init(
    inputTokens: Int? = nil,
    cachedInputTokens: Int? = nil,
    cacheWriteTokens: Int? = nil,
    outputTokens: Int? = nil
  ) {
    let inputTokens = inputTokens.flatMap { $0 >= 0 ? $0 : nil }
    let cachedInputTokens = cachedInputTokens.flatMap { $0 >= 0 ? $0 : nil }
    let cacheWriteTokens = cacheWriteTokens.flatMap { $0 >= 0 ? $0 : nil }
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens.flatMap { $0 >= 0 ? $0 : nil }
    if let inputTokens {
      let read = cachedInputTokens ?? 0
      let write = cacheWriteTokens ?? 0
      // Subtract only after both counts fit, so Int.max inputs cannot overflow.
      let fits = read <= inputTokens && write <= inputTokens && read <= inputTokens - write
      self.cachedInputTokens = fits ? cachedInputTokens : nil
      self.cacheWriteTokens = fits ? cacheWriteTokens : nil
    } else {
      self.cachedInputTokens = cachedInputTokens
      self.cacheWriteTokens = cacheWriteTokens
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let details = try? container.nestedContainer(
      keyedBy: DetailKeys.self, forKey: .inputDetails
    )
    self.init(
      inputTokens: container.tokenCount(.inputTokens),
      cachedInputTokens: container.tokenCount(.cachedInputTokens)
        ?? details?.tokenCount(.cachedTokens),
      cacheWriteTokens: details?.tokenCount(.cacheWriteTokens),
      outputTokens: container.tokenCount(.outputTokens)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case cachedInputTokens = "cached_input_tokens"
    case outputTokens = "output_tokens"
    case inputDetails = "input_tokens_details"
  }

  private enum DetailKeys: String, CodingKey {
    case cachedTokens = "cached_tokens"
    case cacheWriteTokens = "cache_write_tokens"
  }
}

extension KeyedDecodingContainer {
  fileprivate func tokenCount(_ key: Key) -> Int? {
    guard let value = try? decode(Int.self, forKey: key), value >= 0 else { return nil }
    return value
  }
}

public enum LLMRoute: String, Sendable {
  case codexCLI
  case chatGPTResponses
  case openAIResponses
}

/// A successful text request, with no prompt, output, credentials or session IDs.
public struct LLMUsageReport: Sendable, Equatable {
  public let route: LLMRoute
  public let task: LLMTaskKind
  /// The explicit override; nil means the user's existing Codex default.
  public let requestedModel: String?
  /// Only populated when the provider actually reports a model.
  public let responseModel: String?
  public let usage: LLMUsage
  public let duration: Duration

  public init(
    route: LLMRoute,
    task: LLMTaskKind,
    requestedModel: String?,
    responseModel: String?,
    usage: LLMUsage,
    duration: Duration
  ) {
    self.route = route
    self.task = task
    self.requestedModel = requestedModel
    self.responseModel = responseModel
    self.usage = usage
    self.duration = duration
  }
}
