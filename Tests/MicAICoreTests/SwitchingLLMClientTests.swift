import Foundation
import MicAICore
import Testing

@Suite
struct SwitchingLLMClientTests {
  @Test
  func forwardsToTheCurrentClient() async throws {
    let client = SwitchingLLMClient(FixedTransformer(output: "first"))
    #expect(try await client.transform(request()) == "first")

    await client.use(FixedTransformer(output: "second"))
    #expect(try await client.transform(request()) == "second")
  }

  @Test
  func apiKeyClientWithoutAKeyReportsAMissingCredential() async {
    let client = OpenAIAPIKeyClient(apiKey: { "   " })
    do {
      _ = try await client.transform(request())
      Issue.record("Expected credentialMissing")
    } catch {
      #expect(error as? MicAIError == .credentialMissing)
    }
  }

  private func request() -> LLMRequest {
    LLMRequest(instruction: "do it", selectedText: nil, model: "gpt-test")
  }
}

private struct FixedTransformer: LLMTransforming {
  let output: String

  func transform(_ request: LLMRequest) async throws -> String {
    output
  }
}
