import AppKit
@preconcurrency import ApplicationServices
import MicAICore

actor TargetApplicationTracker: TargetValidating {
  private struct FocusSnapshot: @unchecked Sendable {
    let element: AXUIElement
    let selectedRange: CFRange?
  }

  private var focusSnapshots: [UUID: FocusSnapshot] = [:]

  func capture() async -> TargetIdentity? {
    let application = await MainActor.run {
      NSWorkspace.shared.frontmostApplication
    }
    guard let application,
      let focusSnapshot = Self.captureFocus(
        processIdentifier: application.processIdentifier
      )
    else {
      return nil
    }
    let focusToken = UUID()
    focusSnapshots[focusToken] = focusSnapshot
    return TargetIdentity(
      processIdentifier: application.processIdentifier,
      bundleIdentifier: application.bundleIdentifier,
      applicationName: application.localizedName,
      focusToken: focusToken
    )
  }

  func isCurrent(_ target: TargetIdentity) async -> Bool {
    let isFrontmost = await MainActor.run {
      guard let application = NSWorkspace.shared.frontmostApplication else {
        return false
      }
      guard application.processIdentifier == target.processIdentifier else {
        return false
      }
      if let expectedBundleIdentifier = target.bundleIdentifier {
        return application.bundleIdentifier == expectedBundleIdentifier
      }
      return true
    }
    guard isFrontmost,
      let focusToken = target.focusToken,
      let expected = focusSnapshots[focusToken],
      let current = Self.captureFocus(processIdentifier: target.processIdentifier),
      CFEqual(expected.element, current.element)
    else {
      return false
    }
    guard let expectedRange = expected.selectedRange else {
      return true
    }
    guard let currentRange = current.selectedRange else {
      return false
    }
    return expectedRange.location == currentRange.location
      && expectedRange.length == currentRange.length
  }

  func reactivate(_ target: TargetIdentity) async -> Bool {
    guard let focusToken = target.focusToken,
      focusSnapshots[focusToken] != nil
    else {
      return false
    }
    let activated = await MainActor.run {
      guard
        let application = NSRunningApplication(
          processIdentifier: target.processIdentifier
        )
      else {
        return false
      }
      return application.activate(options: [])
    }
    guard activated else {
      return false
    }
    try? await Task.sleep(for: .milliseconds(180))
    return await isCurrent(target)
  }

  func release(_ target: TargetIdentity) {
    guard let focusToken = target.focusToken else {
      return
    }
    focusSnapshots.removeValue(forKey: focusToken)
  }

  private nonisolated static func captureFocus(
    processIdentifier: pid_t
  ) -> FocusSnapshot? {
    let application = AXUIElementCreateApplication(processIdentifier)
    var focusedValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application,
        kAXFocusedUIElementAttribute as CFString,
        &focusedValue
      ) == .success,
      let focusedValue,
      CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
    else {
      return nil
    }

    let focusedElement = focusedValue as! AXUIElement
    return FocusSnapshot(
      element: focusedElement,
      selectedRange: captureSelectedRange(from: focusedElement)
    )
  }

  private nonisolated static func captureSelectedRange(
    from focusedElement: AXUIElement
  ) -> CFRange? {
    var selectedRangeValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        focusedElement,
        kAXSelectedTextRangeAttribute as CFString,
        &selectedRangeValue
      ) == .success,
      let selectedRangeValue,
      CFGetTypeID(selectedRangeValue) == AXValueGetTypeID()
    else {
      return nil
    }
    let axValue = selectedRangeValue as! AXValue
    var selectedRange = CFRange()
    guard AXValueGetType(axValue) == .cfRange,
      AXValueGetValue(axValue, .cfRange, &selectedRange)
    else {
      return nil
    }
    return selectedRange
  }
}
