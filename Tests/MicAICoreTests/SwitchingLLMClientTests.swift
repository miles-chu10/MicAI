import Foundation
import MicAICore
import Testing

@Suite
struct SwitchingLLMClientTests {
  @Test
  func apiKeyConfigurationIgnoresMissingAndWhitespaceValues() {
    #expect(!OpenAIAPIKeyClient.hasKey(in: [:]))
    #expect(!OpenAIAPIKeyClient.hasKey(in: ["OPENAI_API_KEY": " \n "]))
    #expect(OpenAIAPIKeyClient.hasKey(in: ["OPENAI_API_KEY": "fake-key"]))
  }

  @Test
  func switchingSupplierRoutesEachCallToSelectedClient() async throws {
    let selection = ProviderSelection(.chatgptSubscription)
    let chatGPTClient = RecordingLLMClient(output: "subscription")
    let apiKeyClient = RecordingLLMClient(output: "api-key")
    let client = SwitchingLLMClient(
      chatGPTSubscriptionClient: chatGPTClient,
      openAIAPIKeyClient: apiKeyClient,
      providerSupplier: { selection.current() }
    )
    let firstRequest = LLMRequest(
      instruction: "first",
      selectedText: nil,
      model: "gpt-test"
    )
    let secondRequest = LLMRequest(
      instruction: "second",
      selectedText: "selection",
      model: "gpt-test"
    )

    #expect(try await client.transform(firstRequest) == "subscription")
    selection.set(.openAIAPIKey)
    #expect(try await client.transform(secondRequest) == "api-key")

    #expect(await chatGPTClient.requests == [firstRequest])
    #expect(await apiKeyClient.requests == [secondRequest])
  }
}

private actor RecordingLLMClient: LLMTransforming {
  private let output: String
  private(set) var requests: [LLMRequest] = []

  init(output: String) {
    self.output = output
  }

  func transform(_ request: LLMRequest) async throws -> String {
    requests.append(request)
    return output
  }
}

private final class ProviderSelection: @unchecked Sendable {
  private let lock = NSLock()
  private var provider: LLMProvider

  init(_ provider: LLMProvider) {
    self.provider = provider
  }

  func current() -> LLMProvider {
    lock.withLock { provider }
  }

  func set(_ provider: LLMProvider) {
    lock.withLock {
      self.provider = provider
    }
  }
}
