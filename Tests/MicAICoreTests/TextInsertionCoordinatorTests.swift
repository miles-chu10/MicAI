import Foundation
import MicAICore
import Testing

@Suite
struct TextInsertionCoordinatorTests {
  private let target = TargetIdentity(processIdentifier: 42)

  @Test
  func insertionRestoresEveryOriginalItemAndRepresentation() async throws {
    let originalItems = [
      [
        "public.utf8-plain-text": Data("original".utf8),
        "public.rtf": Data([0x7B, 0x5C, 0x72, 0x74, 0x66]),
      ],
      ["public.file-url": Data("file:///tmp/example".utf8)],
    ]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard()
    let validator = FakeTargetValidator(responses: [true, true])
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: validator
    )

    try await coordinator.apply(.insert("dictated text"), to: target)

    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.restoreCount == 1)
    #expect(keyboard.pasteCount == 1)
  }

  @Test
  func externalClipboardChangeIsNeverOverwritten() async throws {
    let pasteboard = FakePasteboard(
      items: [["public.utf8-plain-text": Data("original".utf8)]]
    )
    let keyboard = FakeKeyboard()
    let validator = FakeTargetValidator(responses: [true, true])
    let externalItems = [["public.utf8-plain-text": Data("external".utf8)]]
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: validator,
      delay: { pasteboard.externalWrite(items: externalItems) }
    )

    do {
      try await coordinator.apply(.insert("dictated text"), to: target)
      Issue.record("Expected concurrent clipboard change to be reported")
    } catch {
      #expect(error as? MicAIError == .clipboardChanged)
    }
    #expect(pasteboard.items == externalItems)
    #expect(pasteboard.restoreCount == 0)
    #expect(keyboard.pasteCount == 1)
  }

  @Test
  func focusChangeBeforePasteWithholdsInsertionAndRestoresClipboard() async throws {
    let originalItems = [["public.utf8-plain-text": Data("original".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard()
    let validator = FakeTargetValidator(responses: [true, false])
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: validator
    )

    do {
      try await coordinator.apply(.insert("dictated text"), to: target)
      Issue.record("Expected changed focus to withhold insertion")
    } catch {
      #expect(error as? MicAIError == .targetChanged)
    }
    #expect(pasteboard.items == originalItems)
    #expect(keyboard.pasteCount == 0)
  }

  @Test
  func replacementUsesTheSameGuardedPasteTransaction() async throws {
    let pasteboard = FakePasteboard(items: [])
    let keyboard = FakeKeyboard()
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: FakeTargetValidator(responses: [true, true])
    )

    try await coordinator.apply(.replaceSelection("replacement"), to: target)

    #expect(pasteboard.writtenTexts == ["replacement"])
    #expect(keyboard.pasteCount == 1)
    #expect(pasteboard.restoreCount == 1)
  }

  @Test
  func failedPasteRestoresOriginalClipboardOnce() async throws {
    let originalItems = [["public.utf8-plain-text": Data("original".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard(pasteError: .insertionFailed)
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: FakeTargetValidator(responses: [true, true])
    )

    do {
      try await coordinator.apply(.insert("dictated text"), to: target)
      Issue.record("Expected paste failure to be reported")
    } catch {
      #expect(error as? MicAIError == .insertionFailed)
    }
    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.restoreCount == 1)
  }

  @Test
  func cancellationAfterTemporaryWriteRestoresWithoutPasting() async throws {
    let originalItems = [["public.utf8-plain-text": Data("original".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard()
    let gate = CurrentOperationGate(responses: [true, true, false])
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: FakeTargetValidator(responses: [true])
    )

    do {
      try await coordinator.apply(
        .insert("dictated text"),
        to: target,
        while: { gate.next() }
      )
      Issue.record("Expected cancellation before paste")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }

    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.restoreCount == 1)
    #expect(keyboard.pasteCount == 0)
  }

  @Test
  func clipboardConflictBeforePasteStillReportsCancellation() async throws {
    let originalItems = [["public.utf8-plain-text": Data("original".utf8)]]
    let externalItems = [["public.utf8-plain-text": Data("external".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard()
    let gate = ConflictingCancellationGate(
      pasteboard: pasteboard,
      externalItems: externalItems
    )
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: FakeTargetValidator(responses: [true])
    )

    do {
      try await coordinator.apply(
        .insert("dictated text"),
        to: target,
        while: { gate.next() }
      )
      Issue.record("Expected cancellation before paste")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }

    #expect(pasteboard.items == externalItems)
    #expect(pasteboard.restoreCount == 0)
    #expect(keyboard.pasteCount == 0)
  }

  @Test
  func failedRestoreAfterCancellationIsSurfaced() async throws {
    let pasteboard = FakePasteboard(
      items: [["public.utf8-plain-text": Data("original".utf8)]],
      restoreError: .insertionFailed
    )
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: FakeKeyboard(),
      validator: FakeTargetValidator(responses: [true])
    )
    let gate = CurrentOperationGate(responses: [true, true, false])

    do {
      try await coordinator.apply(
        .insert("dictated text"),
        to: target,
        while: { gate.next() }
      )
      Issue.record("Expected clipboard restoration failure")
    } catch {
      #expect(
        error as? MicAIError == .clipboardRestoreFailedAfterCancellation
      )
    }
  }

  @Test
  func cancellationDuringInitialTargetValidationDoesNotTouchClipboard() async throws {
    let originalItems = [["public.utf8-plain-text": Data("original".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard()
    let validator = SuspendingTargetValidator(suspendOnCall: 1)
    let gate = MutableOperationGate()
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: validator
    )

    let application = Task {
      try await coordinator.apply(
        .insert("dictated text"),
        to: target,
        while: { gate.isCurrent() }
      )
    }
    await validator.waitUntilSuspended()
    gate.cancel()
    await validator.resume(returning: true)

    do {
      try await application.value
      Issue.record("Expected cancellation during initial target validation")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }
    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.writtenTexts.isEmpty)
    #expect(pasteboard.restoreCount == 0)
    #expect(keyboard.pasteCount == 0)
  }

  @Test
  func cancellationDuringPrePasteTargetValidationRestoresWithoutPasting() async throws {
    let originalItems = [["public.utf8-plain-text": Data("original".utf8)]]
    let pasteboard = FakePasteboard(items: originalItems)
    let keyboard = FakeKeyboard()
    let validator = SuspendingTargetValidator(suspendOnCall: 2)
    let gate = MutableOperationGate()
    let coordinator = makeCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      validator: validator
    )

    let application = Task {
      try await coordinator.apply(
        .insert("dictated text"),
        to: target,
        while: { gate.isCurrent() }
      )
    }
    await validator.waitUntilSuspended()
    gate.cancel()
    await validator.resume(returning: true)

    do {
      try await application.value
      Issue.record("Expected cancellation during pre-paste target validation")
    } catch {
      #expect(error as? MicAIError == .cancelled)
    }
    #expect(pasteboard.items == originalItems)
    #expect(pasteboard.writtenTexts == ["dictated text"])
    #expect(pasteboard.restoreCount == 1)
    #expect(keyboard.pasteCount == 0)
  }

  private func makeCoordinator(
    pasteboard: FakePasteboard,
    keyboard: FakeKeyboard,
    validator: any TargetValidating,
    delay: @escaping @Sendable () async -> Void = {}
  ) -> TextInsertionCoordinator {
    TextInsertionCoordinator(
      pasteboard: pasteboard,
      keyboard: keyboard,
      targetValidator: validator,
      delay: delay
    )
  }
}

final class FakePasteboard: PasteboardAccessing, @unchecked Sendable {
  private let lock = NSLock()
  private var storedItems: [[String: Data]]
  private let restoreError: MicAIError?
  private var changeCount = 1
  private var storedRestoreCount = 0
  private var storedWrittenTexts: [String] = []

  init(
    items: [[String: Data]],
    restoreError: MicAIError? = nil
  ) {
    storedItems = items
    self.restoreError = restoreError
  }

  var items: [[String: Data]] {
    locked { storedItems }
  }

  var restoreCount: Int {
    locked { storedRestoreCount }
  }

  var writtenTexts: [String] {
    locked { storedWrittenTexts }
  }

  func snapshot() throws -> PasteboardSnapshot {
    locked {
      PasteboardSnapshot(items: storedItems, changeCount: changeCount)
    }
  }

  func writePlainText(_ text: String) throws -> Int {
    locked {
      changeCount += 1
      storedItems = [["public.utf8-plain-text": Data(text.utf8)]]
      storedWrittenTexts.append(text)
      return changeCount
    }
  }

  func restore(_ snapshot: PasteboardSnapshot) throws {
    try locked {
      if let restoreError {
        throw restoreError
      }
      changeCount += 1
      storedItems = snapshot.items
      storedRestoreCount += 1
    }
  }

  func currentChangeCount() -> Int {
    locked { changeCount }
  }

  func externalWrite(items: [[String: Data]]) {
    locked {
      changeCount += 1
      storedItems = items
    }
  }

  private func locked<T>(_ operation: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

final class FakeKeyboard: KeyboardSynthesizing, @unchecked Sendable {
  private let lock = NSLock()
  private let onCopy: @Sendable () -> Void
  private let pasteError: MicAIError?
  private var storedCopyCount = 0
  private var storedPasteCount = 0

  init(
    onCopy: @escaping @Sendable () -> Void = {},
    pasteError: MicAIError? = nil
  ) {
    self.onCopy = onCopy
    self.pasteError = pasteError
  }

  var copyCount: Int {
    locked { storedCopyCount }
  }

  var pasteCount: Int {
    locked { storedPasteCount }
  }

  func copy() throws {
    locked { storedCopyCount += 1 }
    onCopy()
  }

  func paste() throws {
    locked { storedPasteCount += 1 }
    if let pasteError {
      throw pasteError
    }
  }

  private func locked<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }
}

actor FakeTargetValidator: TargetValidating {
  private var responses: [Bool]

  init(responses: [Bool]) {
    self.responses = responses
  }

  func isCurrent(_ target: TargetIdentity) async -> Bool {
    responses.isEmpty ? true : responses.removeFirst()
  }
}

final class CurrentOperationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [Bool]

  init(responses: [Bool]) {
    self.responses = responses
  }

  func next() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return responses.isEmpty ? true : responses.removeFirst()
  }
}

final class ConflictingCancellationGate: @unchecked Sendable {
  private let lock = NSLock()
  private let pasteboard: FakePasteboard
  private let externalItems: [[String: Data]]
  private var invocationCount = 0

  init(
    pasteboard: FakePasteboard,
    externalItems: [[String: Data]]
  ) {
    self.pasteboard = pasteboard
    self.externalItems = externalItems
  }

  func next() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    invocationCount += 1
    if invocationCount == 3 {
      pasteboard.externalWrite(items: externalItems)
      return false
    }
    return true
  }
}

final class MutableOperationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var current = true

  func isCurrent() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  func cancel() {
    lock.lock()
    current = false
    lock.unlock()
  }
}

actor SuspendingTargetValidator: TargetValidating {
  private let suspendOnCall: Int
  private var callCount = 0
  private var validationContinuation: CheckedContinuation<Bool, Never>?
  private var waitContinuation: CheckedContinuation<Void, Never>?

  init(suspendOnCall: Int) {
    self.suspendOnCall = suspendOnCall
  }

  func isCurrent(_ target: TargetIdentity) async -> Bool {
    callCount += 1
    guard callCount == suspendOnCall else {
      return true
    }
    return await withCheckedContinuation { continuation in
      validationContinuation = continuation
      waitContinuation?.resume()
      waitContinuation = nil
    }
  }

  func waitUntilSuspended() async {
    guard validationContinuation == nil else {
      return
    }
    await withCheckedContinuation { continuation in
      waitContinuation = continuation
    }
  }

  func resume(returning result: Bool) {
    let continuation = validationContinuation
    validationContinuation = nil
    continuation?.resume(returning: result)
  }
}
