import Foundation

public actor TextInsertionCoordinator {
  private let pasteboard: any PasteboardAccessing
  private let keyboard: any KeyboardSynthesizing
  private let targetValidator: any TargetValidating
  private let delay: @Sendable () async -> Void

  public init(
    pasteboard: any PasteboardAccessing,
    keyboard: any KeyboardSynthesizing,
    targetValidator: any TargetValidating,
    delay: @escaping @Sendable () async -> Void = {
      try? await Task.sleep(for: .milliseconds(120))
    }
  ) {
    self.pasteboard = pasteboard
    self.keyboard = keyboard
    self.targetValidator = targetValidator
    self.delay = delay
  }

  public func readSelection(from target: TargetIdentity? = nil) async throws -> String? {
    if let target, !(await targetValidator.isCurrent(target)) {
      throw MicAIError.targetChanged
    }

    let original = try pasteboard.snapshot()
    do {
      try keyboard.copy()
    } catch {
      throw MicAIError.insertionFailed
    }
    await delay()

    let copied = try pasteboard.snapshot()
    guard copied.changeCount != original.changeCount else {
      return nil
    }
    if let target, !(await targetValidator.isCurrent(target)) {
      try restore(original, ifCurrentChangeCountIs: copied.changeCount)
      throw MicAIError.targetChanged
    }
    let selection = SelectionResult(snapshot: copied)
    try restore(original, ifCurrentChangeCountIs: copied.changeCount)

    switch selection {
    case .text(let text):
      return text
    case .noSelection:
      return nil
    }
  }

  public func copyResult(_ text: String) throws {
    guard !text.isEmpty else {
      throw MicAIError.insertionFailed
    }
    do {
      _ = try pasteboard.writePlainText(text)
    } catch {
      throw MicAIError.insertionFailed
    }
  }

  public func apply(
    _ intent: InsertionIntent,
    to target: TargetIdentity,
    while operationIsCurrent: @escaping @Sendable () async -> Bool = { true }
  ) async throws {
    guard await operationIsCurrent() else {
      throw MicAIError.cancelled
    }
    guard await targetValidator.isCurrent(target) else {
      throw MicAIError.targetChanged
    }
    guard await operationIsCurrent() else {
      throw MicAIError.cancelled
    }

    let original = try pasteboard.snapshot()
    let text: String
    switch intent {
    case .insert(let insertion), .replaceSelection(let insertion):
      text = insertion
    }

    let writtenChangeCount: Int
    do {
      writtenChangeCount = try pasteboard.writePlainText(text)
    } catch {
      throw MicAIError.insertionFailed
    }

    guard await operationIsCurrent() else {
      try restoreBeforePaste(
        original,
        ifCurrentChangeCountIs: writtenChangeCount,
        primaryError: .cancelled,
        restorationError: .clipboardRestoreFailedAfterCancellation
      )
    }
    guard await targetValidator.isCurrent(target) else {
      try restoreBeforePaste(
        original,
        ifCurrentChangeCountIs: writtenChangeCount,
        primaryError: .targetChanged,
        restorationError: .clipboardRestoreFailedAfterTargetChange
      )
    }
    guard await operationIsCurrent() else {
      try restoreBeforePaste(
        original,
        ifCurrentChangeCountIs: writtenChangeCount,
        primaryError: .cancelled,
        restorationError: .clipboardRestoreFailedAfterCancellation
      )
    }

    do {
      try keyboard.paste()
    } catch {
      try restoreBeforePaste(
        original,
        ifCurrentChangeCountIs: writtenChangeCount,
        primaryError: .insertionFailed,
        restorationError: .clipboardRestoreFailedBeforeInsertion
      )
    }

    await delay()
    do {
      try restore(original, ifCurrentChangeCountIs: writtenChangeCount)
    } catch let error as MicAIError where error == .clipboardChanged {
      throw error
    } catch {
      throw MicAIError.clipboardRestoreFailedAfterInsertion
    }
  }

  private func restoreBeforePaste(
    _ snapshot: PasteboardSnapshot,
    ifCurrentChangeCountIs expectedChangeCount: Int,
    primaryError: MicAIError,
    restorationError: MicAIError
  ) throws -> Never {
    do {
      try restore(
        snapshot,
        ifCurrentChangeCountIs: expectedChangeCount
      )
    } catch let error as MicAIError where error == .clipboardChanged {
      throw primaryError
    } catch {
      throw restorationError
    }
    throw primaryError
  }

  private func restore(
    _ snapshot: PasteboardSnapshot,
    ifCurrentChangeCountIs expectedChangeCount: Int
  ) throws {
    guard pasteboard.currentChangeCount() == expectedChangeCount else {
      throw MicAIError.clipboardChanged
    }
    do {
      try pasteboard.restore(snapshot)
    } catch {
      throw MicAIError.insertionFailed
    }
  }
}
