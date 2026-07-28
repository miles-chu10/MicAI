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

    Divider()

    Label(
      appModel.operationPhase.displayName,
      systemImage: appModel.operationPhase.systemImage
    )

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
