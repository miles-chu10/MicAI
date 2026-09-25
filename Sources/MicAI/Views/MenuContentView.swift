import AppKit
import MicAICore
import SwiftUI

/// The menu bar menu: status first, then your shortcuts, then actions.
///
/// It stays a real `NSMenu` (the default `MenuBarExtra` style) rather than a
/// custom popover, so it gets keyboard navigation, VoiceOver and the system's
/// look for free, and behaves like every other menu bar extra.
struct MenuContentView: View {
  @ObservedObject var appModel: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(statusLine)

    if let errorMessage = appModel.errorMessage, !appModel.isOperationActive {
      Text(errorMessage)
    }

    if appModel.isOperationActive {
      Button("Cancel Current Operation") {
        appModel.cancelCurrentOperation()
      }
    }

    Divider()

    Section("Shortcuts") {
      ForEach(MicAIMode.builtIn, id: \.self) { mode in
        if let hotkey = appModel.settingsStore.settings.hotkey(for: mode) {
          Text("\(mode.shortName)    \(hotkey.displayName)")
        }
      }
      ForEach(appModel.settingsStore.settings.customModes) { customMode in
        if let hotkey = customMode.hotkey {
          Text("\(customMode.name)    \(hotkey.displayName)")
        }
      }
    }

    Divider()

    Button("Paste Last Result") {
      appModel.pasteLastResult()
    }
    .disabled(appModel.lastResult == nil || appModel.isOperationActive)

    Button("Copy Last Result") {
      appModel.copyLastResult()
    }
    .disabled(appModel.lastResult == nil)

    Divider()

    Button("Open MicAI") {
      open("main")
    }
    .keyboardShortcut("0", modifiers: .command)

    Button("History…") {
      open("history")
    }
    .keyboardShortcut("y", modifiers: [.command, .shift])

    if !appModel.readiness.dictation.isReady {
      Button("Finish Setup…") {
        appModel.showOnboarding()
        open("main")
      }
    }

    Divider()

    Toggle(
      "Privacy Mode",
      isOn: Binding(
        get: { appModel.settingsStore.settings.privacyMode },
        set: { appModel.setPrivacyMode($0) }
      )
    )

    SettingsLink {
      Text("Settings…")
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Button("Quit MicAI") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }

  private var statusLine: String {
    if appModel.settingsStore.settings.privacyMode {
      return "Privacy mode · nothing leaves this Mac"
    }
    if appModel.isOperationActive {
      return appModel.operationPhase.displayName
    }
    return appModel.readiness.dictation.isReady
      ? "Ready · speech on this Mac" : "Setup needed"
  }

  private func open(_ id: String) {
    NSApplication.shared.activate(ignoringOtherApps: true)
    openWindow(id: id)
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
      .keyboardShortcut("y", modifiers: [.command, .shift])

      Button("Copy Last Result") {
        appModel.copyLastResult()
      }
      .disabled(appModel.lastResult == nil)

      Button("Cancel Current Operation") {
        appModel.cancelCurrentOperation()
      }
      .keyboardShortcut(.cancelAction)
      .disabled(!appModel.isOperationActive)

      Button("Download Speech Model") {
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
    Image(systemName: symbol)
      .accessibilityLabel("MicAI")
      .onChange(of: appModel.pendingAnswer?.id) { _, newValue in
        guard newValue != nil else {
          return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "answer")
      }
  }

  private var symbol: String {
    if appModel.isOperationActive {
      return "mic.fill"
    }
    if appModel.settingsStore.settings.privacyMode {
      return "mic.slash"
    }
    return "mic"
  }
}
