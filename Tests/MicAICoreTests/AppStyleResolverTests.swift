import Foundation
import MicAICore
import Testing

@Suite
struct AppStyleResolverTests {
  @Test
  func userOverrideBeatsBuiltInTable() {
    let resolver = AppStyleResolver(
      overrides: ["com.tinyspeck.slackmacgap": .professional]
    )

    #expect(resolver.tone(for: target(bundle: "com.tinyspeck.slackmacgap")) == .professional)
  }

  @Test
  func builtInTableResolvesKnownBundleIdentifiers() {
    let resolver = AppStyleResolver()

    #expect(resolver.tone(for: target(bundle: "com.tinyspeck.slackmacgap")) == .casual)
    #expect(resolver.tone(for: target(bundle: "com.apple.mail")) == .professional)
    #expect(resolver.tone(for: target(bundle: "com.apple.dt.Xcode")) == .technical)
  }

  @Test
  func unknownBundleIdentifierFallsBackToApplicationName() {
    let resolver = AppStyleResolver()
    let unknownSlack = target(
      bundle: "com.example.slack-nightly-build",
      name: "Slack Nightly"
    )

    #expect(resolver.tone(for: unknownSlack) == .casual)
  }

  @Test
  func nameMatchIsCaseInsensitive() {
    let resolver = AppStyleResolver()

    #expect(resolver.tone(for: target(bundle: nil, name: "XCODE")) == .technical)
  }

  @Test
  func unrecognizedTargetUsesDefaultTone() {
    let resolver = AppStyleResolver(defaultTone: .professional)
    let unknown = target(bundle: "com.example.unknown", name: "Zzyzx")

    #expect(resolver.tone(for: unknown) == .professional)
    #expect(resolver.tone(for: nil) == .professional)
  }

  @Test
  func moreSpecificNameKeywordWinsOverBroaderOne() {
    // "Microsoft Teams" contains neither a code nor a chat keyword before
    // "teams", so ordering must keep it professional rather than casual.
    let resolver = AppStyleResolver()

    #expect(resolver.tone(for: target(bundle: nil, name: "Microsoft Teams")) == .professional)
  }

  private func target(bundle: String?, name: String? = nil) -> TargetIdentity {
    TargetIdentity(
      processIdentifier: 42,
      bundleIdentifier: bundle,
      applicationName: name
    )
  }
}
