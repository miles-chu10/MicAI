import MicAICore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
  case general
  case style
  case vocabulary
  case snippets
  case privacy

  var id: Self { self }

  var title: String {
    switch self {
    case .general:
      "General"
    case .style:
      "Style"
    case .vocabulary:
      "Vocabulary"
    case .snippets:
      "Snippets"
    case .privacy:
      "Privacy"
    }
  }

  var symbol: String {
    switch self {
    case .general:
      "gearshape"
    case .style:
      "textformat"
    case .vocabulary:
      "character.book.closed"
    case .snippets:
      "text.quote"
    case .privacy:
      "hand.raised"
    }
  }

  /// Vocabulary and snippets save as you add them; the other panes edit a
  /// draft that is validated as a whole, because a hotkey collision spans
  /// fields no single toggle could check.
  var usesDraft: Bool {
    switch self {
    case .general, .style, .privacy:
      true
    case .vocabulary, .snippets:
      false
    }
  }
}

/// Settings, laid out like System Settings: a sidebar of panes, each a grouped
/// form. One draft is shared across panes so switching panes never loses an
/// edit, and one Save validates everything together.
struct SettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject private var store: SettingsStore
  @State private var draft: AppSettings
  @State private var pane: SettingsPane? = .general

  init(appModel: AppModel) {
    self.appModel = appModel
    _store = ObservedObject(wrappedValue: appModel.settingsStore)
    _draft = State(initialValue: appModel.settingsStore.settings)
  }

  var body: some View {
    NavigationSplitView {
      List(SettingsPane.allCases, selection: $pane) { pane in
        Label(pane.title, systemImage: pane.symbol)
          .tag(pane)
      }
      .navigationSplitViewColumnWidth(190)
      .toolbar(removing: .sidebarToggle)
      .safeAreaInset(edge: .bottom) {
        SidebarStatus(appModel: appModel)
      }
    } detail: {
      detail
        .navigationTitle((pane ?? .general).title)
        .safeAreaInset(edge: .bottom) {
          if (pane ?? .general).usesDraft {
            saveBar
          }
        }
    }
    .frame(minWidth: 760, minHeight: 560)
    .onAppear { draft = store.settings }
  }

  @ViewBuilder
  private var detail: some View {
    switch pane ?? .general {
    case .general:
      GeneralSettingsPane(appModel: appModel, draft: $draft)
    case .style:
      StyleSettingsPane(appModel: appModel, draft: $draft)
    case .vocabulary:
      VocabularySettingsPane(appModel: appModel)
    case .snippets:
      SnippetsSettingsPane(appModel: appModel)
    case .privacy:
      PrivacySettingsPane(appModel: appModel, draft: $draft)
    }
  }

  private var saveBar: some View {
    HStack(spacing: 10) {
      if let message = store.validationMessage {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .font(.callout)
      } else if draft != store.settings {
        Text("Unsaved changes")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Revert") {
        draft = store.settings
      }
      .disabled(draft == store.settings)
      Button("Save") {
        if store.save(draft) {
          draft = store.settings
          appModel.applySettings()
        }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(draft == store.settings)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(.bar)
  }
}

/// "Ready · speech model on this Mac", at the foot of the sidebar.
private struct SidebarStatus: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    let ready = appModel.readiness.dictation.isReady
    HStack(spacing: 7) {
      Circle()
        .fill(ready ? Color.green : Color.orange)
        .frame(width: 7, height: 7)
      Text(ready ? "Ready · speech on this Mac" : "Setup needed")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

// MARK: - General

struct GeneralSettingsPane: View {
  @ObservedObject var appModel: AppModel
  @Binding var draft: AppSettings
  @State private var apiKeyEntry = ""

  var body: some View {
    Form {
      Section {
        ShortcutRow(
          mode: .dictation,
          selection: Binding(
            get: { draft.dictationHotkey },
            set: { if let value = $0 { draft.dictationHotkey = value } }
          ),
          options: Self.dictationHotkeys,
          allowsOff: false
        )
        Picker("Activation", selection: $draft.dictationActivationMode) {
          ForEach(DictationActivationMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        ShortcutRow(
          mode: .command,
          selection: $draft.commandHotkey,
          options: Self.commandHotkeys,
          allowsOff: true
        )
        ShortcutRow(
          mode: .translate,
          selection: $draft.translateHotkey,
          options: Self.translateHotkeys,
          allowsOff: true
        )
        ShortcutRow(
          mode: .ask,
          selection: $draft.askHotkey,
          options: Self.askHotkeys,
          allowsOff: true
        )
      } header: {
        Text("Shortcuts")
      } footer: {
        Text(activationHint)
      }

      Section("Speech recognition") {
        Picker("Model", selection: $draft.speechModel) {
          ForEach(SpeechModelChoice.allCases, id: \.self) { choice in
            VStack(alignment: .leading, spacing: 2) {
              Text(choice.displayName)
              Text(choice.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .tag(choice)
          }
        }
        .pickerStyle(.radioGroup)
        LabeledContent("Status") {
          ModelStatusView(state: appModel.modelState, prepare: appModel.prepareModel)
        }
        Toggle("Play sounds when recording starts and finishes", isOn: $draft.soundFeedback)
      }

      Section {
        Picker("Provider", selection: $draft.llmProvider) {
          ForEach(LLMProvider.allCases, id: \.self) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        if draft.llmProvider == .openAIAPIKey {
          apiKeyRow
        }
        TextField("Model", text: $draft.llmModel, prompt: Text("Model name"))
        TextField(
          "Translate into",
          text: $draft.translationTargetLanguage,
          prompt: Text("Spanish")
        )
        Toggle("Always open Ask AI answers in a window", isOn: $draft.askAlwaysOpensWindow)
        LabeledContent("Status", value: appModel.providerStatus.summary)
      } header: {
        Text("Language model")
      } footer: {
        Text(providerFooter)
      }

      Section("Readiness") {
        ReadinessRow(
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
        ReadinessRow(
          title: "Accessibility",
          ready: appModel.accessibilityPermission.isTrusted,
          readyText: "Allowed",
          blockedText: "Required"
        ) {
          appModel.requestAccessibilityPermission()
        }
        Toggle(
          "Launch MicAI at login",
          isOn: Binding(
            get: { appModel.launchAtLogin.isEnabled },
            set: { appModel.launchAtLogin.setEnabled($0) }
          )
        )
        if let launchError = appModel.launchAtLogin.errorMessage {
          Text(launchError)
            .foregroundStyle(.red)
        }
        Button("Run Setup Again…") {
          appModel.showOnboarding()
        }
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var apiKeyRow: some View {
    LabeledContent("API key") {
      HStack {
        if appModel.hasAPIKey {
          Label("Saved in your Keychain", systemImage: "key.fill")
            .foregroundStyle(.secondary)
          Button("Remove") {
            appModel.removeAPIKey()
          }
        } else {
          SecureField("API key", text: $apiKeyEntry, prompt: Text("sk-…"))
            .labelsHidden()
            .frame(maxWidth: 220)
          Button("Save Key") {
            appModel.saveAPIKey(apiKeyEntry)
            apiKeyEntry = ""
          }
          .disabled(apiKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private var activationHint: String {
    switch draft.dictationActivationMode {
    case .hold:
      "Hold the dictation key while you speak. Command, Translate and Ask AI are always "
        + "hold-to-talk."
    case .toggle:
      "Press the dictation key once to start and again to stop."
    case .hybrid:
      "Hold the dictation key to talk, or tap it once to keep recording hands-free until "
        + "you press it again."
    }
  }

  private var providerFooter: String {
    switch draft.llmProvider {
    case .chatGPTSubscription:
      "Uses the ChatGPT sign-in Codex stored on this Mac. MicAI reads it and never copies it."
    case .openAIAPIKey:
      "Billed to your OpenAI platform account. The key stays in your Keychain."
    }
  }

  static let dictationHotkeys: [Hotkey] = [.rightOption, .controlOptionSpace, .commandShiftSpace]
  static let commandHotkeys: [Hotkey] = [.controlOptionSpace, .commandShiftSpace]
  static let translateHotkeys: [Hotkey] = [
    .controlOptionT,
    .commandShiftSpace,
    .controlOptionSpace,
  ]
  static let askHotkeys: [Hotkey] = [.controlOptionA, .commandShiftSpace, .controlOptionSpace]
}

/// A mode's name, what it does, and its shortcut drawn as keycaps that open a
/// menu of the supported choices.
private struct ShortcutRow: View {
  let mode: MicAIMode
  @Binding var selection: Hotkey?
  let options: [Hotkey]
  let allowsOff: Bool

  var body: some View {
    HStack(spacing: 10) {
      ModeDot(mode: mode)
      VStack(alignment: .leading, spacing: 2) {
        Text(mode.shortName)
        Text(mode.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Menu {
        Picker(mode.shortName, selection: $selection) {
          if allowsOff {
            Text("Off").tag(Hotkey?.none)
          }
          ForEach(options, id: \.self) { hotkey in
            Text(hotkey.displayName).tag(Hotkey?.some(hotkey))
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      } label: {
        if let selection {
          KeyCaps(selection)
        } else {
          Text("Off")
            .foregroundStyle(.secondary)
        }
      }
      .menuStyle(.button)
      .buttonStyle(.borderless)
      .fixedSize()
      .accessibilityLabel("\(mode.shortName) shortcut")
    }
  }
}
