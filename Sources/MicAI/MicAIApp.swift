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

    MenuBarExtra("MicAI", systemImage: "mic.fill") {
      MenuContentView(appModel: appModel)
    }

    Settings {
      SettingsView(appModel: appModel)
    }
  }
}
