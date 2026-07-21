import AppKit
import MicAICore

actor TargetApplicationTracker: TargetValidating {
  func capture() async -> TargetIdentity? {
    await MainActor.run {
      guard let application = NSWorkspace.shared.frontmostApplication else {
        return nil
      }
      return TargetIdentity(
        processIdentifier: application.processIdentifier,
        bundleIdentifier: application.bundleIdentifier,
        applicationName: application.localizedName
      )
    }
  }

  func isCurrent(_ target: TargetIdentity) async -> Bool {
    await MainActor.run {
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
  }
}
