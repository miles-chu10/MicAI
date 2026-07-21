import Foundation
import MicAICore
import Testing

@Suite
struct SelectionCaptureTests {
  @Test
  func copiedPlainTextIsReturnedAndOriginalClipboardIsRestored() async throws {
    let originalItems = [["public.rtf": Data([0x01, 0x02])]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard {
      pasteboard.externalWrite(
        items: [["public.utf8-plain-text": Data("selected text".utf8)]]
      )
    }
    let coordinator = TextInsertionCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      targetValidator: FakeTargetValidator(responses: []),
      delay: {}
    )

    let selection = try await coordinator.readSelection()

    #expect(selection == "selected text")
    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.restoreCount == 1)
    #expect(keyboard.copyCount == 1)
  }

  @Test
  func copyThatDoesNotChangePasteboardMeansNoSelection() async throws {
    let originalItems = [["public.utf8-plain-text": Data("stale".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let coordinator = TextInsertionCoordinator(
      pasteboard: pasteboard,
      keyboard: FakeKeyboard(),
      targetValidator: FakeTargetValidator(responses: []),
      delay: {}
    )

    #expect(try await coordinator.readSelection() == nil)
    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.restoreCount == 0)
  }

  @Test
  func copiedNonTextDataMeansNoSelectionAndStillRestores() async throws {
    let originalItems = [["public.utf8-plain-text": Data("original".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard {
      pasteboard.externalWrite(items: [["public.png": Data([0x89, 0x50])]])
    }
    let coordinator = TextInsertionCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      targetValidator: FakeTargetValidator(responses: []),
      delay: {}
    )

    #expect(try await coordinator.readSelection() == nil)
    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.restoreCount == 1)
  }
}
