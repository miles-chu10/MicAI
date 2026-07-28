import AppKit
@preconcurrency import ApplicationServices
import Combine

@MainActor
final class AccessibilityPermissionService: ObservableObject {
  @Published private(set) var isTrusted = AXIsProcessTrusted()

  func refresh() {
    isTrusted = AXIsProcessTrusted()
  }

  func requestPrompt() {
    let options =
      [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
      ] as CFDictionary
    isTrusted = AXIsProcessTrustedWithOptions(options)
  }

  func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
