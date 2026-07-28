import MicAICore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject private var store: SettingsStore
  @State private var draft: AppSettings
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openWindow) private var openWindow

  init(appModel: AppModel) {
    self.appModel = appModel
    _store = ObservedObject(wrappedValue: appModel.settingsStore)
    _draft = State(initialValue: appModel.settingsStore.settings)
  }

  var body: some View {
    VStack(spacing: 0) {
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
          LabeledContent("Authentication", value: "ChatGPT sign-in")
          LabeledContent("Status", value: appModel.providerStatus.summary)
          Text(
            "MicAI uses your existing Codex sign-in with ChatGPT for subscription access."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Readiness") {
          SettingsStatusRow(
            title: "Microphone",
            ready: appModel.microphonePermission.isGranted,
            readyText: "Allowed",
            blockedText: "Required",
            actionTitle: appModel.microphonePermission.status == .undetermined
              ? "Request Access…" : "Open Settings…"
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
            blockedText: "Required",
            actionTitle: "Request Access…"
          ) {
            appModel.requestAccessibilityPermission()
          }

          LabeledContent("Local speech model") {
            HStack(spacing: 10) {
              Text(modelStatus)
              if case .preparing(let fraction, _) = appModel.modelState {
                ProgressView(value: fraction)
                  .frame(width: 90)
                  .accessibilityLabel("Speech model preparation")
              } else if appModel.modelState != .ready {
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
            Label {
              Text(launchError)
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            }
          }
        }

        if let validationMessage = store.validationMessage {
          Label {
            Text(validationMessage)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          }
        }
      }
      .formStyle(.grouped)
      .scenePadding()

      Divider()
      HStack {
        Button("Run Setup Again", systemImage: "checklist") {
          appModel.showOnboarding()
          dismiss()
          MainWindowPresenter.show(using: openWindow)
        }
        Spacer()
        if draft != store.settings {
          Text("Unsaved changes")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Button("Save", systemImage: "checkmark") {
          if store.save(draft) {
            draft = store.settings
            appModel.applySettings()
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(draft == store.settings)
      }
      .padding(16)
      .background(.bar)
    }
    .frame(width: 560, height: 680)
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
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    LabeledContent(title) {
      HStack {
        Label {
          Text(ready ? readyText : blockedText)
        } icon: {
          Image(
            systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
          )
          .foregroundStyle(ready ? Color.green : Color.orange)
        }
        if !ready {
          Button(actionTitle, action: action)
        }
      }
    }
  }
}
