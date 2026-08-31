import MicAICore
import SwiftUI

struct SettingsView: View {
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

        Section("Transcription") {
          Picker("Provider", selection: $draft.dictationProvider) {
            ForEach(DictationProvider.allCases) { provider in
              Text(provider.displayName).tag(provider)
            }
          }
          .accessibilityHint("Chooses the provider used for ordinary dictation.")

          if draft.dictationProvider == .openAI {
            TextField(
              "OpenAI model",
              text: $draft.openAITranscriptionModel,
              prompt: Text(SpeechTranscriptionRequest.defaultOpenAIModel)
            )
            .accessibilityHint(
              "Enter gpt-transcribe or another supported transcription model ID."
            )

            if isOpenAIModelEmpty {
              Label(
                "Enter an OpenAI transcription model before saving.",
                systemImage: "exclamationmark.circle.fill"
              )
              .font(.footnote)
              .foregroundStyle(MicAIStatusColor.danger)
              .accessibilityLabel("OpenAI model is required")
            }

            Toggle(
              "Use Parakeet when OpenAI is unavailable",
              isOn: $draft.openAITranscriptionFallbackEnabled
            )
            .accessibilityHint(
              "Keeps ordinary dictation on-device when OpenAI cannot run."
            )

            LabeledContent("API access") {
              SettingsAvailabilityLabel(
                title: "Not configured",
                systemImage: "xmark.circle.fill",
                tint: MicAIStatusColor.attention
              )
            }
            LabeledContent("Billing") {
              SettingsAvailabilityLabel(
                title: "Not verified",
                systemImage: "questionmark.circle.fill",
                tint: .secondary
              )
            }
            LabeledContent("First live transcription") {
              SettingsAvailabilityLabel(
                title: "Not run",
                systemImage: "circle.dashed",
                tint: .secondary
              )
            }
            Text(
              "MicAI does not store an API key yet. Saving this selection does not contact OpenAI."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          } else {
            Label(
              "Ordinary dictation is transcribed on this Mac with Parakeet.",
              systemImage: "lock.shield.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }

          LabeledContent("Effective route") {
            Text(effectiveDraftRoute)
              .multilineTextAlignment(.trailing)
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
            "Personal-use preview using the local Codex sign-in. This is not a supported public OpenAI API authentication method."
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
    .frame(width: 580, height: 760)
    .onAppear {
      draft = store.settings
    }
  }

  private var hasUnsavedChanges: Bool {
    draft != store.settings
  }

  private var isOpenAIModelEmpty: Bool {
    draft.dictationProvider == .openAI
      && draft.openAITranscriptionModel
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

  private var effectiveDraftRoute: String {
    switch draft.dictationProvider {
    case .parakeet:
      return appModel.modelState == .ready
        ? "Parakeet on-device" : "Prepare Parakeet"
    case .openAI:
      if draft.openAITranscriptionFallbackEnabled {
        return appModel.modelState == .ready
          ? "Parakeet fallback until OpenAI is configured"
          : "Prepare the Parakeet fallback"
      }
      return "Blocked until OpenAI is configured"
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

private struct SettingsAvailabilityLabel: View {
  let title: String
  let systemImage: String
  let tint: Color

  var body: some View {
    Label(title, systemImage: systemImage)
      .foregroundStyle(tint)
      .accessibilityElement(children: .combine)
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
