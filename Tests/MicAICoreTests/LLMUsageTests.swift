import Foundation
import MicAICore
import Testing

struct LLMUsageTests {
  @Test(arguments: [
    #"{"input_tokens":100,"cached_input_tokens":101,"output_tokens":2}"#,
    #"{"input_tokens":100,"input_tokens_details":{"cached_tokens":20,"cache_write_tokens":101}}"#,
    #"{"input_tokens":100,"input_tokens_details":{"cached_tokens":60,"cache_write_tokens":41}}"#,
    #"{"input_tokens":9223372036854775807,"input_tokens_details":{"cached_tokens":9223372036854775807,"cache_write_tokens":1}}"#,
  ])
  func inconsistentCacheCountsBecomeUnknown(_ body: String) throws {
    let usage = try JSONDecoder().decode(LLMUsage.self, from: Data(body.utf8))
    #expect(usage.inputTokens != nil)
    #expect(usage.cachedInputTokens == nil)
    #expect(usage.cacheWriteTokens == nil)
  }

  @Test
  func exactInputBoundaryIsValidWithoutOverflow() {
    let usage = LLMUsage(inputTokens: Int.max, cachedInputTokens: Int.max - 1, cacheWriteTokens: 1)
    #expect(usage.cachedInputTokens == Int.max - 1)
    #expect(usage.cacheWriteTokens == 1)
    #expect(
      LLMUsage(inputTokens: 100, cachedInputTokens: 60, cacheWriteTokens: 40).cachedInputTokens
        == 60)
  }

  @Test
  func unknownInputDoesNotInventATotalOrDiscardKnownCacheCounts() throws {
    let body = #"{"cached_input_tokens":20,"input_tokens_details":{"cache_write_tokens":10}}"#
    let usage = try JSONDecoder().decode(LLMUsage.self, from: Data(body.utf8))
    #expect(usage.inputTokens == nil)
    #expect(usage.cachedInputTokens == 20)
    #expect(usage.cacheWriteTokens == 10)
    #expect(usage.outputTokens == nil)
  }
}
