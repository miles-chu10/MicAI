import MicAICore
import SwiftUI

/// What leaves the machine, and what is kept on it.
struct PrivacySettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject private var store: SettingsStore
  @State private var draft: AppSettings
  @State private var isConfirmingClear = false

  init(appModel: AppModel) {
    self.appModel = appModel
    _store = ObservedObject(wrappedValue: appModel.settingsStore)
    _draft = State(initialValue: appModel.settingsStore.settings)
  }

  var body: some View {
    Form {
      Section("Privacy mode") {
        Toggle("Keep everything on this Mac", isOn: $draft.privacyMode)
        Text(
          "Speech recognition already runs locally on this Mac and audio is "
            + "never uploaded. Privacy mode additionally stops transcripts from "
            + "being sent for AI clean-up, and disables AI Commands. Turning it "
            + "off restores your previous settings."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("History") {
        Toggle("Keep a history of dictations", isOn: $draft.historyEnabled)
        Text("Stored on this Mac only, in Application Support. Never uploaded.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Stepper(
          "Keep the last \(draft.historyLimit) entries",
          value: $draft.historyLimit,
          in: 10...2_000,
          step: 10
        )
        .disabled(!draft.historyEnabled)

        LabeledContent("Stored now") {
          Text("\(appModel.historyEntries.count)")
            .monospacedDigit()
        }

        Button("Clear History…", role: .destructive) {
          isConfirmingClear = true
        }
        .disabled(appModel.historyEntries.isEmpty)
      }

      if let validationMessage = store.validationMessage {
        Label {
          Text(validationMessage)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(MicAIStatusColor.danger)
        }
      }

      HStack {
        Spacer()
        Button("Save", systemImage: "checkmark") {
          if store.save(draft) {
            draft = store.settings
            appModel.applySettings()
            // Turning history off should not leave the old entries on disk —
            // the toggle reads as a privacy promise, so honor it literally.
            if !draft.historyEnabled {
              appModel.clearHistory()
            }
          }
        }
        .micAIPrimaryButtonStyle()
        .keyboardShortcut(.defaultAction)
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear { draft = store.settings }
    .confirmationDialog(
      "Clear all dictation history?",
      isPresented: $isConfirmingClear,
      titleVisibility: .visible
    ) {
      Button("Clear History", role: .destructive) {
        appModel.clearHistory()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This cannot be undone. Learned vocabulary is kept.")
    }
  }
}
