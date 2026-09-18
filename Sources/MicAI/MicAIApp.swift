import AppKit
import SwiftUI

@main
struct MicAIApp: App {
  @StateObject private var appModel = AppModel()

  var body: some Scene {
    WindowGroup("MicAI", id: "main") {
      PrimaryAppView(appModel: appModel)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
          NSApplication.shared.activate(ignoringOtherApps: true)
          appModel.refreshSystemStatus()
        }
        .onReceive(
          NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
          )
        ) { _ in
          appModel.refreshSystemStatus()
        }
        .onReceive(
          NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification
          )
        ) { _ in
          appModel.stopRuntime()
        }
    }
    .defaultSize(width: 940, height: 640)
    .defaultPosition(.center)
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unified)
    .commands {
      MicAICommands(appModel: appModel)
    }

    Window("History", id: "history") {
      HistoryView(appModel: appModel)
    }
    .defaultSize(width: 860, height: 520)
    .defaultPosition(.center)

    Window("Ask AI", id: "answer") {
      AskAnswerView(appModel: appModel)
    }
    .defaultSize(width: 520, height: 380)
    .defaultPosition(.center)

    // The label form is used deliberately: unlike the menu's content, the label
    // view is always instantiated, so it is the one place in a menu-bar-only app
    // that can hold an observer and still reach `openWindow`.
    MenuBarExtra {
      MenuContentView(appModel: appModel)
    } label: {
      MenuBarLabel(appModel: appModel)
    }

    Settings {
      SettingsView(appModel: appModel)
    }
  }
}
