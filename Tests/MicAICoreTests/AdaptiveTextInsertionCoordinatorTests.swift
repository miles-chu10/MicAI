import Foundation
import MicAICore
import Testing

@Suite
struct AdaptiveTextInsertionCoordinatorTests {
  private let target = TargetIdentity(processIdentifier: 42)

  @Test
  func directInsertionLeavesClipboardUntouched() async throws {
    let direct = FakeDirectTextInserter(result: true)
    let pasteboard = FakePasteboard(
      items: [["public.utf8-plain-text": Data("original".utf8)]]
    )
    let coordinator = makeCoordinator(
      direct: direct,
      pasteboard: pasteboard
    )

    try await coordinator.apply(.insert("dictated text"), to: target)

    #expect(await direct.insertedTexts == ["dictated text"])
    #expect(pasteboard.writtenTexts.isEmpty)
    #expect(pasteboard.restoreCount == 0)
  }

  @Test
  func fallsBackToGuardedClipboardInsertion() async throws {
    let direct = FakeDirectTextInserter(result: false)
    let pasteboard = FakePasteboard(items: [])
    let coordinator = makeCoordinator(
      direct: direct,
      pasteboard: pasteboard
    )

    try await coordinator.apply(.replaceSelection("replacement"), to: target)

    #expect(await direct.insertedTexts == ["replacement"])
    #expect(pasteboard.writtenTexts == ["replacement"])
    #expect(pasteboard.restoreCount == 1)
  }

  @Test
  func cancellationBeforeInsertionTouchesNothing() async {
    let direct = FakeDirectTextInserter(result: true)
    let pasteboard = FakePasteboard(items: [])
    let coordinator = makeCoordinator(
      direct: direct,
      pasteboard: pasteboard
    )

    do {
      try await coordinator.apply(
        .insert("ignored"),
        to: target,
        while: { false }
      )
      Issue.record("Expected cancellation")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }

    #expect(await direct.insertedTexts.isEmpty)
    #expect(pasteboard.writtenTexts.isEmpty)
  }

  private func makeCoordinator(
    direct: FakeDirectTextInserter,
    pasteboard: FakePasteboard
  ) -> AdaptiveTextInsertionCoordinator {
    AdaptiveTextInsertionCoordinator(
      directInserter: direct,
      clipboardFallback: TextInsertionCoordinator(
        pasteboard: pasteboard,
        keyboard: FakeKeyboard(),
        targetValidator: FakeTargetValidator(responses: [true, true]),
        delay: {}
      )
    )
  }
}

private actor FakeDirectTextInserter: DirectTextInserting {
  private let result: Bool
  private(set) var insertedTexts: [String] = []

  init(result: Bool) {
    self.result = result
  }

  func insert(_ text: String, into target: TargetIdentity) async -> Bool {
    insertedTexts.append(text)
    return result
  }
}
