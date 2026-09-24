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
    .frame(width: 560, height: 620)
  }
}

struct GeneralSettingsView: View {
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
          "Codex model override",
          text: $draft.llmModel,
          prompt: Text("Optional — blank uses your Codex default")
        )
        LabeledContent("Provider", value: appModel.providerStatus.summary)
      }

      Section("AI Translate") {
        Picker(
          "Hotkey",
          selection: $draft.translateHotkey
        ) {
          Text("Not configured").tag(nil as Hotkey?)
          ForEach(Self.translateHotkeys, id: \.self) { hotkey in
            Text(hotkey.displayName).tag(hotkey as Hotkey?)
          }
        }
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
        Picker(
          "Hotkey",
          selection: $draft.askHotkey
        ) {
          Text("Not configured").tag(nil as Hotkey?)
          ForEach(Self.askHotkeys, id: \.self) { hotkey in
            Text(hotkey.displayName).tag(hotkey as Hotkey?)
          }
        }
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

  private static let translateHotkeys: [Hotkey] = [
    .controlOptionT,
    .commandShiftSpace,
    .controlOptionSpace,
  ]

  private static let askHotkeys: [Hotkey] = [
    .controlOptionA,
    .commandShiftSpace,
    .controlOptionSpace,
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
