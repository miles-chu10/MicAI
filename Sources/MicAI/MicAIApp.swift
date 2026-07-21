import AppKit
import MicAICore
import SwiftUI

@main
struct MicAIApp: App {
  @StateObject private var settingsStore = SettingsStore()

  var body: some Scene {
    MenuBarExtra("MicAI", systemImage: "mic.fill") {
      VStack(alignment: .leading, spacing: 8) {
        Text("MicAI")
          .font(.headline)
        Label("Idle", systemImage: "circle")
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)

      Divider()

      SettingsLink {
        Label("Settings…", systemImage: "gearshape")
      }

      Button("Quit MicAI") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }

    Settings {
      SettingsView(store: settingsStore)
    }
  }
}

private struct SettingsView: View {
  @ObservedObject var store: SettingsStore

  var body: some View {
    Form {
      Section("Dictation") {
        LabeledContent("Hotkey", value: "Right Option")
        Picker("Activation", selection: $store.settings.dictationActivationMode) {
          ForEach(DictationActivationMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
      }

      Section("Command") {
        LabeledContent("Hotkey", value: "Not configured")
      }

      Section("Language model") {
        TextField("Model", text: $store.settings.llmModel)
          .textFieldStyle(.roundedBorder)
      }

      if let validationMessage = store.validationMessage {
        Text(validationMessage)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Save") {
          store.save()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 440)
  }
}
