import AppKit
import SwiftUI

@main
struct MicAIApp: App {
  @StateObject private var appModel = AppModel()

  var body: some Scene {
    WindowGroup("MicAI", id: "main") {
      PrimaryAppView(appModel: appModel)
        .frame(minWidth: 640, minHeight: 520)
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
    .defaultSize(width: 820, height: 680)
    .defaultPosition(.center)
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unified)
    .commands {
      MicAICommands(appModel: appModel)
    }

    Window("History", id: "history") {
      HistoryView(appModel: appModel)
    }
    .defaultSize(width: 920, height: 580)
    .defaultPosition(.center)

    Window("Ask AI", id: "answer") {
      AskAnswerView(appModel: appModel)
    }
    .defaultSize(width: 540, height: 440)
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
