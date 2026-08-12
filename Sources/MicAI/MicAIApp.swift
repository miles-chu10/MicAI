import AppKit
import SwiftUI

@main
struct MicAIApp: App {
  @NSApplicationDelegateAdaptor(MicAIApplicationDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("MicAI", systemImage: "mic.fill") {
      MenuContentView(appModel: appDelegate.appModel)
    }
    .commands {
      SidebarCommands()
      MicAICommands(appModel: appDelegate.appModel)
    }

    Settings {
      SettingsView(appModel: appDelegate.appModel)
    }
  }
}

@MainActor
final class MicAIApplicationDelegate: NSObject, NSApplicationDelegate {
  let appModel = AppModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    if ProcessInfo.processInfo.environment["MICAI_UI_FIXTURE"]?.hasPrefix("hud-")
      == true
    {
      return
    }
    MainWindowPresenter.install(appModel: appModel)
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    appModel.refreshSystemStatus()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    MainWindowPresenter.show()
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationWillTerminate(_ notification: Notification) {
    appModel.stopRuntime()
  }
}
