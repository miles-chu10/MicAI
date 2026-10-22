import Foundation

/// Parses `codex exec --json` without exposing progress, tools or usage as text.
public struct CodexJSONParser: Sendable {
  private var buffer = Data()
  private var output: String?
  private var completed = false
  private var pendingError: MicAIError?
  public private(set) var usage = LLMUsage()

  public init() {}

  public mutating func append(_ data: Data) throws {
    buffer.append(data)
    while let newline = buffer.firstIndex(of: 0x0A) {
      let line = buffer.subdata(in: buffer.startIndex..<newline)
      buffer.removeSubrange(buffer.startIndex...newline)
      try process(line)
    }
  }

  public mutating func finish() throws -> String {
    if !buffer.isEmpty {
      try process(buffer)
      buffer.removeAll()
    }
    guard completed else {
      throw pendingError ?? MicAIError.llmIncomplete
    }
    guard let output,
      !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw MicAIError.llmIncomplete
    }
    return output
  }

  private mutating func process(_ line: Data) throws {
    if line.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) { return }
    guard let event = try? JSONDecoder().decode(Event.self, from: line) else {
      throw MicAIError.llmIncomplete
    }
    switch event.type {
    case "item.completed":
      guard !completed else { throw MicAIError.llmIncomplete }
      if let item = event.item, item.type == "agent_message",
        item.phase == nil || item.phase == "final_answer"
      {
        guard let text = item.text else { throw MicAIError.llmIncomplete }
        output = text
      }
    case "turn.completed":
      guard !completed else { throw MicAIError.llmIncomplete }
      completed = true
      usage = event.usage ?? LLMUsage()
    case "turn.failed", "error":
      let message = (event.message ?? event.error?.message ?? "").lowercased()
      let unauthorized =
        message.contains("401 unauthorized") || message.contains("not logged in")
        || message.contains("run codex login")
      let error: MicAIError = unauthorized ? .llmUnauthorized : .llmServerFailure
      if event.type == "turn.failed" || completed {
        throw error
      }
      // A recoverable stream error may precede a successful CLI retry.
      // Only terminal turn failure or EOF without completion rejects the text.
      pendingError = error
    default:
      break
    }
  }
}

private struct Event: Decodable {
  let type: String
  let item: Item?
  let usage: LLMUsage?
  let message: String?
  let error: Failure?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(String.self, forKey: .type)
    item = try container.decodeIfPresent(Item.self, forKey: .item)
    usage = try? container.decode(LLMUsage.self, forKey: .usage)
    message = try? container.decode(String.self, forKey: .message)
    error = try? container.decode(Failure.self, forKey: .error)
  }

  struct Item: Decodable {
    let type: String
    let text: String?
    let phase: String?
  }

  struct Failure: Decodable {
    let message: String?
  }

  enum CodingKeys: String, CodingKey {
    case type, item, usage, message, error
  }
}
