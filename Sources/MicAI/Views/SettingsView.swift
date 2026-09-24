import MicAICore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    TabView {
      GeneralSettingsView(appModel: appModel)
        .tabItem { Label("General", systemImage: "gearshape") }

      StyleSettingsView(appModel: appModel)
        .tabItem { Label("Style", systemImage: "wand.and.stars") }

      VocabularySettingsView(appModel: appModel)
        .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }

      PrivacySettingsView(appModel: appModel)
        .tabItem { Label("Privacy", systemImage: "hand.raised") }
    }
    .frame(width: 600, height: 780)
  }
}

struct GeneralSettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject private var store: SettingsStore
  @State private var draft: AppSettings
  @Environment(\.dismiss) private var dismiss

  init(appModel: AppModel) {
    self.appModel = appModel
    _store = ObservedObject(wrappedValue: appModel.settingsStore)
    _draft = State(initialValue: appModel.settingsStore.settings)
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Dictation") {
          HotkeyRecorderField(
            title: "Hotkey",
            hotkey: Binding(
              get: { draft.dictationHotkey },
              set: { if let hotkey = $0 { draft.dictationHotkey = hotkey } }
            ),
            allowsNone: false
          )

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
          HotkeyRecorderField(title: "Hotkey", hotkey: $draft.commandHotkey)
          TextField(
            "Codex model override",
            text: $draft.llmModel,
            prompt: Text("Optional — blank uses your Codex default")
          )
          LabeledContent("Provider", value: appModel.providerStatus.summary)
        }

        Section("AI Translate") {
          HotkeyRecorderField(title: "Hotkey", hotkey: $draft.translateHotkey)
          TextField(
            "Translate into",
            text: $draft.translationTargetLanguage,
            prompt: Text("Spanish")
          )
          Text(
            "With text selected, the selection is translated in place. With nothing "
              + "selected, what you say is translated and inserted. Speech is "
              + "recognized in English on device; the selection can be any language."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section("Ask AI") {
          HotkeyRecorderField(title: "Hotkey", hotkey: $draft.askHotkey)
          Toggle("Always open answers in a window", isOn: $draft.askAlwaysOpensWindow)
          Text(
            "Ask a question and the answer opens in a window. Say something that is "
              + "not a question and it is typed at your cursor instead. Any selected "
              + "text is used as context and is never overwritten."
          )
          .font(.caption)
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
                .foregroundStyle(MicAIStatusColor.danger)
            }
          }
        }

        if let validationMessage = store.validationMessage {
          Label {
            Text(validationMessage)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(MicAIStatusColor.danger)
          }
        }
      }
      .formStyle(.grouped)
      .scenePadding()

      Divider()
      MicAIActionCluster {
        HStack {
          Button("Run Setup Again", systemImage: "checklist") {
            appModel.showOnboarding()
            dismiss()
            MainWindowPresenter.show()
          }
          .micAISecondaryButtonStyle()
          .disabled(hasUnsavedChanges)
          .help(
            hasUnsavedChanges
              ? "Save or discard your settings changes before running setup again"
              : "Open the guided MicAI setup"
          )

          Spacer()
          if hasUnsavedChanges {
            Text("Unsaved changes")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          Button("Revert", systemImage: "arrow.uturn.backward") {
            draft = store.settings
            store.discardValidation()
          }
          .micAISecondaryButtonStyle()
          .disabled(!hasUnsavedChanges)
          .help("Discard unsaved settings changes")

          Button("Save", systemImage: "checkmark") {
            if store.save(draft) {
              draft = store.settings
              appModel.applySettings()
            }
          }
          .micAIPrimaryButtonStyle()
          .keyboardShortcut(.defaultAction)
          .disabled(
            !hasUnsavedChanges || !isDraftValid || !appModel.canApplySettings
          )
          .help(
            saveHelp
          )
        }
      }
      .padding(16)
      .background(.bar)
    }
    .onAppear {
      draft = store.settings
    }
  }

  private var hasUnsavedChanges: Bool {
    draft != store.settings
  }

  private var isDraftValid: Bool {
    (try? draft.validated()) != nil
  }

  private var saveHelp: String {
    if !hasUnsavedChanges {
      return "Change a setting before saving"
    }
    if !appModel.canApplySettings {
      return "Finish or cancel the current operation before saving"
    }
    if !isDraftValid {
      return "Resolve the validation message before saving"
    }
    return "Save MicAI settings"
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
          .foregroundStyle(ready ? MicAIStatusColor.ready : MicAIStatusColor.attention)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          "\(title): \(ready ? readyText : blockedText)"
        )
        if !ready {
          Button(actionTitle, action: action)
            .accessibilityHint("Opens the recovery action for \(title).")
        }
      }
    }
  }
}
