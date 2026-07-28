import AppKit
import SwiftUI

@MainActor
enum MainWindowPresenter {
  static func show(using openWindow: OpenWindowAction) {
    NSApplication.shared.activate(ignoringOtherApps: true)

    if let window = NSApplication.shared.windows.first(where: isPrimaryWindow) {
      window.deminiaturize(nil)
      window.makeKeyAndOrderFront(nil)
      return
    }

    openWindow(id: "main")
  }

  private static func isPrimaryWindow(_ window: NSWindow) -> Bool {
    window.canBecomeMain
      && window.sheetParent == nil
      && !(window is NSPanel)
      && window.title != "MicAI Settings"
  }
}
