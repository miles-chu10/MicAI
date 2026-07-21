import Foundation

public struct SSEParser: Sendable {
  private var buffer = Data()
  private var output = ""
  private var completed = false

  public init() {}

  public mutating func append(_ data: Data) throws {
    buffer.append(data)
    try drainCompleteFrames()
  }

  public mutating func finish() throws -> String {
    if !buffer.isEmpty {
      try process(frame: buffer)
      buffer.removeAll(keepingCapacity: false)
    }
    guard completed else {
      throw MicAIError.llmIncomplete
    }
    guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MicAIError.llmIncomplete
    }
    return output
  }

  private mutating func drainCompleteFrames() throws {
    while let boundary = nextBoundary() {
      let frame = buffer.subdata(in: buffer.startIndex..<boundary.range.lowerBound)
      buffer.removeSubrange(buffer.startIndex..<boundary.range.upperBound)
      try process(frame: frame)
    }
  }

  private func nextBoundary() -> (range: Range<Data.Index>, length: Int)? {
    let lineFeed = Data([0x0A, 0x0A])
    let carriageReturn = Data([0x0D, 0x0A, 0x0D, 0x0A])
    let lineFeedRange = buffer.range(of: lineFeed)
    let carriageReturnRange = buffer.range(of: carriageReturn)

    switch (lineFeedRange, carriageReturnRange) {
    case (.none, .none):
      return nil
    case (.some(let range), .none):
      return (range, lineFeed.count)
    case (.none, .some(let range)):
      return (range, carriageReturn.count)
    case (.some(let left), .some(let right)):
      return left.lowerBound <= right.lowerBound
        ? (left, lineFeed.count) : (right, carriageReturn.count)
    }
  }

  private mutating func process(frame: Data) throws {
    guard !frame.isEmpty, let raw = String(data: frame, encoding: .utf8) else {
      return
    }
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
    let payload = normalized.split(separator: "\n", omittingEmptySubsequences: false)
      .compactMap { line -> Substring? in
        guard line.hasPrefix("data:") else {
          return nil
        }
        var value = line.dropFirst(5)
        if value.first == " " {
          value = value.dropFirst()
        }
        return value
      }
      .joined(separator: "\n")

    guard !payload.isEmpty, payload != "[DONE]" else {
      return
    }
    guard let data = payload.data(using: .utf8) else {
      throw MicAIError.llmIncomplete
    }

    let event: Event
    do {
      event = try JSONDecoder().decode(Event.self, from: data)
    } catch {
      throw MicAIError.llmIncomplete
    }

    switch event.type {
    case "response.output_text.delta":
      guard !completed, let delta = event.delta else {
        throw MicAIError.llmIncomplete
      }
      output += delta
    case "response.completed":
      completed = true
    case "response.failed", "response.incomplete", "error":
      throw MicAIError.llmIncomplete
    default:
      break
    }
  }
}

private struct Event: Decodable {
  let type: String
  let delta: String?
}
