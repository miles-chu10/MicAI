import AppKit
import SwiftUI

struct MenuContentView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    Button("Open MicAI", systemImage: "macwindow") {
      MainWindowPresenter.show()
    }
    .keyboardShortcut("0", modifiers: .command)

    Divider()

    Label {
      Text("Status: \(appModel.operationPhase.displayName)")
    } icon: {
      Image(systemName: appModel.operationPhase.systemImage)
    }

    Label {
      Text("Dictation: \(appModel.dictationEffectiveRouteLabel)")
    } icon: {
      Image(
        systemName: appModel.settingsStore.settings.dictationProvider == .openAI
          ? "cloud.fill" : "waveform"
      )
    }

    if appModel.isOperationActive {
      Button("Cancel Current Operation", systemImage: "xmark.circle") {
        appModel.cancelCurrentOperation()
      }
      .keyboardShortcut(.cancelAction)
    }

    if !appModel.readiness.dictation.isSetupReady {
      Button("Review Setup…", systemImage: "checklist") {
        appModel.showOnboarding()
        MainWindowPresenter.show()
      }
    }

    if appModel.recoverableInsertion != nil {
      Divider()

      Button("Retry Last Insertion", systemImage: "arrow.clockwise") {
        appModel.retryRecoverableInsertion()
      }
      .disabled(appModel.isRecoveringInsertion)

      Button("Copy Last Result", systemImage: "doc.on.doc") {
        appModel.copyRecoverableResult()
      }
      .disabled(appModel.isRecoveringInsertion)

      Button("Dismiss Last Result", systemImage: "xmark") {
        appModel.dismissRecoverableInsertion()
      }
      .disabled(appModel.isRecoveringInsertion)
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

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Open MicAI", systemImage: "macwindow") {
        MainWindowPresenter.show()
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

      Divider()

      Button("Retry Last Insertion", systemImage: "arrow.clockwise") {
        appModel.retryRecoverableInsertion()
      }
      .disabled(
        appModel.recoverableInsertion == nil || appModel.isRecoveringInsertion
      )

      Button("Copy Last Result", systemImage: "doc.on.doc") {
        appModel.copyRecoverableResult()
      }
      .disabled(
        appModel.recoverableInsertion == nil || appModel.isRecoveringInsertion
      )
    }
  }
}
