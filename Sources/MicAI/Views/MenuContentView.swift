import AppKit
import SwiftUI

struct MenuContentView: View {
  @ObservedObject var appModel: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open MicAI") {
      NSApplication.shared.activate(ignoringOtherApps: true)
      openWindow(id: "main")
    }
    .keyboardShortcut("0", modifiers: .command)

    Button("History…") {
      NSApplication.shared.activate(ignoringOtherApps: true)
      openWindow(id: "history")
    }
    .keyboardShortcut("y", modifiers: [.command, .shift])

    Divider()

    Label(
      appModel.operationPhase.displayName,
      systemImage: appModel.operationPhase.systemImage
    )

    if appModel.settingsStore.settings.privacyMode {
      Label("Privacy mode — nothing leaves this Mac", systemImage: "hand.raised.fill")
    }

    if appModel.isOperationActive {
      Button("Cancel Current Operation") {
        appModel.cancelCurrentOperation()
      }
      .keyboardShortcut(.cancelAction)
    }

    if !appModel.readiness.dictation.isReady {
      Button("Review Setup…") {
        appModel.showOnboarding()
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main")
      }
    }

    Divider()

    SettingsLink {
      Label("Settings…", systemImage: "gearshape")
    }

    Button("Quit MicAI") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }
}

struct MicAICommands: Commands {
  let appModel: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Open MicAI") {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main")
      }
      .keyboardShortcut("0", modifiers: .command)
    }

    CommandMenu("Dictation") {
      Button("History…") {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "history")
      }

      Button("Cancel Current Operation") {
        appModel.cancelCurrentOperation()
      }
      .keyboardShortcut(.cancelAction)
      .disabled(!appModel.isOperationActive)

      Button("Prepare Local Speech Model") {
        appModel.prepareModel()
      }
      .disabled(appModel.modelState == .ready)
    }
  }
}

/// The menu bar icon, and the only always-instantiated view in the app.
///
/// It carries the observer that raises the Ask AI answer window: a menu's
/// content is built on open, so it cannot react to an answer arriving while the
/// menu is closed, and `openWindow` is reachable only from a view.
struct MenuBarLabel: View {
  @ObservedObject var appModel: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Image(systemName: appModel.isOperationActive ? "mic.fill" : "mic")
      .onChange(of: appModel.pendingAnswer?.id) { _, newValue in
        guard newValue != nil else {
          return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "answer")
      }
  }
}
