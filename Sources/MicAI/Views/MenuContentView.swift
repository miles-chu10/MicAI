import AppKit
import SwiftUI

struct MenuContentView: View {
  @ObservedObject var appModel: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open MicAI", systemImage: "macwindow") {
      MainWindowPresenter.show(using: openWindow)
    }
    .keyboardShortcut("0", modifiers: .command)

    Divider()

    Label {
      Text("Status: \(appModel.operationPhase.displayName)")
    } icon: {
      Image(systemName: appModel.operationPhase.systemImage)
    }

    if appModel.isOperationActive {
      Button("Cancel Current Operation", systemImage: "xmark.circle") {
        appModel.cancelCurrentOperation()
      }
      .keyboardShortcut(.cancelAction)
    }

    if !appModel.readiness.dictation.isReady {
      Button("Review Setup…", systemImage: "checklist") {
        appModel.showOnboarding()
        MainWindowPresenter.show(using: openWindow)
      }
    }

    Divider()

    SettingsLink {
      Label("Settings…", systemImage: "gearshape")
    }

    Button("Quit MicAI", systemImage: "power") {
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
      Button("Open MicAI", systemImage: "macwindow") {
        MainWindowPresenter.show(using: openWindow)
      }
      .keyboardShortcut("0", modifiers: .command)
    }

    CommandMenu("Dictation") {
      Button("Cancel Current Operation", systemImage: "xmark.circle") {
        appModel.cancelCurrentOperation()
      }
      .keyboardShortcut(.cancelAction)
      .disabled(!appModel.isOperationActive)

      Button("Prepare Local Speech Model", systemImage: "arrow.down.circle") {
        appModel.prepareModel()
      }
      .disabled(appModel.modelState == .ready)
    }
  }
}
