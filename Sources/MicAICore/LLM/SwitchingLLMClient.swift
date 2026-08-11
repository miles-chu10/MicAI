public actor SwitchingLLMClient: LLMTransforming {
  private let chatGPTSubscriptionClient: any LLMTransforming
  private let openAIAPIKeyClient: any LLMTransforming
  private let providerSupplier: @Sendable () -> LLMProvider

  public init(
    chatGPTSubscriptionClient: any LLMTransforming,
    openAIAPIKeyClient: any LLMTransforming,
    providerSupplier: @escaping @Sendable () -> LLMProvider
  ) {
    self.chatGPTSubscriptionClient = chatGPTSubscriptionClient
    self.openAIAPIKeyClient = openAIAPIKeyClient
    self.providerSupplier = providerSupplier
  }

  public func transform(_ request: LLMRequest) async throws -> String {
    switch providerSupplier() {
    case .chatgptSubscription:
      try await chatGPTSubscriptionClient.transform(request)
    case .openAIAPIKey:
      try await openAIAPIKeyClient.transform(request)
    }
  }
}
