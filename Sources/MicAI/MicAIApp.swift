import AppKit
import MicAICore
import SwiftUI

@main
struct MicAIApp: App {
  @StateObject private var appModel = AppModel()

  var body: some Scene {
    MenuBarExtra("MicAI", systemImage: "mic.fill") {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("MicAI")
            .font(.headline)
          Spacer()
          Text(phaseLabel)
            .foregroundStyle(.secondary)
        }

        if appModel.operationPhase == .recording {
          ProgressView(value: appModel.inputLevel)
            .accessibilityLabel("Microphone input level")
        }

        ModelStatusView(
          state: appModel.modelState,
          transcript: appModel.lastTranscript,
          prepare: appModel.prepareModel
        )

        Divider()

        permissionControls

        if let errorMessage = appModel.errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      .padding(.horizontal)
      .frame(width: 320)

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
      SettingsView(store: appModel.settingsStore) {
        appModel.applySettings()
      }
    }
  }

  @ViewBuilder
  private var permissionControls: some View {
    if appModel.microphonePermission.isGranted {
      Label("Microphone ready", systemImage: "mic.fill")
    } else {
      Button("Allow Microphone") {
        appModel.requestMicrophonePermission()
      }
    }

    if appModel.accessibilityPermission.isTrusted {
      Label("Accessibility ready", systemImage: "checkmark.shield.fill")
    } else {
      Button("Allow Accessibility") {
        appModel.requestAccessibilityPermission()
      }
    }
  }

  private var phaseLabel: String {
    switch appModel.operationPhase {
    case .idle:
      "Idle"
    case .recording:
      "Recording"
    case .transcribing:
      "Transcribing"
    case .awaitingLLM:
      "Waiting"
    case .inserting:
      "Inserting"
    case .failed:
      "Failed"
    }
  }
}

private struct SettingsView: View {
  @ObservedObject var store: SettingsStore
  let didSave: () -> Void

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
          if store.save() {
            didSave()
          }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 440)
  }
}
