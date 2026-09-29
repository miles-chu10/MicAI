import Foundation

/// One client the engines share, whose provider can change at runtime.
///
/// Refinement, commands, translation and Ask AI all hold the same transformer.
/// Swapping the provider in Settings replaces what this forwards to, rather
/// than rebuilding four engines and the pipelines that own them.
public actor SwitchingLLMClient: LLMTransforming {
  private var current: any LLMTransforming

  public init(_ initial: any LLMTransforming) {
    current = initial
  }

  public func use(_ client: any LLMTransforming) {
    current = client
  }

  public func transform(_ request: LLMRequest) async throws -> String {
    // Captured before awaiting, so a request already in flight finishes on the
    // provider it started with even if Settings switches mid-way.
    let client = current
    return try await client.transform(request)
  }
}
