import AppKit
import SwiftUI

@main
struct MicAIApp: App {
  @NSApplicationDelegateAdaptor(MicAIApplicationDelegate.self) private var appDelegate

  var body: some Scene {
    Window("History", id: "history") {
      HistoryView(appModel: appDelegate.appModel)
    }
    .defaultSize(width: 860, height: 520)
    .defaultPosition(.center)

    Window("Ask AI", id: "answer") {
      AskAnswerView(appModel: appDelegate.appModel)
    }
    .defaultSize(width: 520, height: 380)
    .defaultPosition(.center)

    // The label form is used deliberately: unlike the menu's content, the label
    // view is always instantiated, so it is the one place in a menu-bar-only app
    // that can hold an observer and still reach `openWindow`.
    MenuBarExtra {
      MenuContentView(appModel: appDelegate.appModel)
    } label: {
      MenuBarLabel(appModel: appDelegate.appModel)
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
