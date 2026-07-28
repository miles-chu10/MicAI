import MicAICore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject private var store: SettingsStore
  @State private var draft: AppSettings

  init(appModel: AppModel) {
    self.appModel = appModel
    _store = ObservedObject(wrappedValue: appModel.settingsStore)
    _draft = State(initialValue: appModel.settingsStore.settings)
  }

  var body: some View {
    Form {
      Section("Dictation") {
        Picker(
          "Hotkey",
          selection: $draft.dictationHotkey
        ) {
          ForEach(Self.dictationHotkeys, id: \.self) { hotkey in
            Text(hotkey.displayName).tag(hotkey)
          }
        }

        Picker(
          "Activation",
          selection: $draft.dictationActivationMode
        ) {
          ForEach(DictationActivationMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
      }

      Section("AI Commands") {
        Picker(
          "Hotkey",
          selection: $draft.commandHotkey
        ) {
          Text("Not configured").tag(nil as Hotkey?)
          ForEach(Self.commandHotkeys, id: \.self) { hotkey in
            Text(hotkey.displayName).tag(hotkey as Hotkey?)
          }
        }
        TextField(
          "ChatGPT model",
          text: $draft.llmModel,
          prompt: Text("Enter a supported subscription model")
        )
        LabeledContent("Provider", value: appModel.providerStatus.summary)
      }

      Section("Readiness") {
        SettingsStatusRow(
          title: "Microphone",
          ready: appModel.microphonePermission.isGranted,
          readyText: "Allowed",
          blockedText: "Required"
        ) {
          if appModel.microphonePermission.status == .undetermined {
            appModel.requestMicrophonePermission()
          } else {
            appModel.microphonePermission.openSystemSettings()
          }
        }

        SettingsStatusRow(
          title: "Accessibility",
          ready: appModel.accessibilityPermission.isTrusted,
          readyText: "Allowed",
          blockedText: "Required"
        ) {
          appModel.requestAccessibilityPermission()
        }

        LabeledContent("Local speech model") {
          HStack {
            Text(modelStatus)
            if appModel.modelState != .ready {
              Button("Prepare") {
                appModel.prepareModel()
              }
            }
          }
        }
      }

      Section("System") {
        Toggle(
          "Launch MicAI at login",
          isOn: Binding(
            get: { appModel.launchAtLogin.isEnabled },
            set: { appModel.launchAtLogin.setEnabled($0) }
          )
        )
        LabeledContent("Login item", value: appModel.launchAtLogin.status.label)
        if let launchError = appModel.launchAtLogin.errorMessage {
          Text(launchError)
            .foregroundStyle(.red)
        }
      }

      if let validationMessage = store.validationMessage {
        Text(validationMessage)
          .foregroundStyle(.red)
      }

      HStack {
        Button("Run Setup Again") {
          appModel.showOnboarding()
        }
        Spacer()
        Button("Save") {
          if store.save(draft) {
            draft = store.settings
            appModel.applySettings()
          }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 540, height: 600)
    .onAppear {
      draft = store.settings
    }
  }

  private var modelStatus: String {
    switch appModel.modelState {
    case .notDownloaded:
      "Not prepared"
    case .preparing(_, let phase):
      phase
    case .ready:
      "Ready"
    case .failed:
      "Preparation failed"
    }
  }

  private static let dictationHotkeys: [Hotkey] = [
    .rightOption,
    .controlOptionSpace,
    .commandShiftSpace,
  ]

  private static let commandHotkeys: [Hotkey] = [
    .controlOptionSpace,
    .commandShiftSpace,
  ]
}

private struct SettingsStatusRow: View {
  let title: String
  let ready: Bool
  let readyText: String
  let blockedText: String
  let action: () -> Void

  var body: some View {
    LabeledContent(title) {
      HStack {
        Label(
          ready ? readyText : blockedText,
          systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .foregroundStyle(ready ? Color.green : Color.secondary)
        if !ready {
          Button("Fix…", action: action)
        }
      }
    }
  }
}
