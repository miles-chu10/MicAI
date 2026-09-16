import MicAICore
import SwiftUI

/// Controls what happens to a transcript between the recognizer and the cursor.
struct StyleSettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject private var store: SettingsStore
  @State private var draft: AppSettings
  @State private var newOverrideBundleID = ""
  @State private var newOverrideTone: StyleTone = .casual

  init(appModel: AppModel) {
    self.appModel = appModel
    _store = ObservedObject(wrappedValue: appModel.settingsStore)
    _draft = State(initialValue: appModel.settingsStore.settings)
  }

  var body: some View {
    Form {
      Section("Clean-up") {
        Toggle("Polish dictation with AI", isOn: $draft.refinementEnabled)
        Text(
          "Removes filler words, false starts, and self-corrections, then fixes "
            + "punctuation to match the app you are typing into. Your words and "
            + "meaning are preserved. If the model is unreachable, the raw "
            + "transcript is inserted instead."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if draft.privacyMode {
          Label(
            "Privacy mode is on, so clean-up is disabled.",
            systemImage: "hand.raised.fill"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        } else if draft.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Label(
            "Set a ChatGPT model in General to enable clean-up.",
            systemImage: "exclamationmark.circle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section("Tone") {
        Picker("Default tone", selection: $draft.defaultTone) {
          ForEach(StyleTone.allCases, id: \.self) { tone in
            Text(tone.displayName).tag(tone)
          }
        }
        Text(draft.defaultTone.shortDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(
          "MicAI recognizes common apps automatically — Slack and Messages get a "
            + "casual tone, Mail and Outlook a professional one, editors and "
            + "terminals a technical one. The default above applies to everything else."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Per-app overrides") {
        if draft.styleOverrides.isEmpty {
          Text("No overrides. Add one when MicAI guesses wrong for an app.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        ForEach(draft.styleOverrides.keys.sorted(), id: \.self) { bundleID in
          HStack {
            Text(bundleID)
              .font(.system(.body, design: .monospaced))
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer()
            Picker(
              "",
              selection: Binding(
                get: { draft.styleOverrides[bundleID] ?? .neutral },
                set: { draft.styleOverrides[bundleID] = $0 }
              )
            ) {
              ForEach(StyleTone.allCases, id: \.self) { tone in
                Text(tone.displayName).tag(tone)
              }
            }
            .labelsHidden()
            .frame(width: 140)
            Button {
              draft.styleOverrides.removeValue(forKey: bundleID)
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove override for \(bundleID)")
          }
        }

        HStack {
          TextField(
            "Bundle identifier",
            text: $newOverrideBundleID,
            prompt: Text("com.example.app")
          )
          .font(.system(.body, design: .monospaced))
          Picker("", selection: $newOverrideTone) {
            ForEach(StyleTone.allCases, id: \.self) { tone in
              Text(tone.displayName).tag(tone)
            }
          }
          .labelsHidden()
          .frame(width: 140)
          Button("Add", action: addOverride)
            .disabled(trimmedNewBundleID.isEmpty)
        }

        if let bundleID = appModel.historyEntries.first?.bundleIdentifier {
          Button("Use last dictation target (\(bundleID))") {
            newOverrideBundleID = bundleID
          }
          .font(.caption)
          .buttonStyle(.borderless)
        }
      }

      HStack {
        Spacer()
        Button("Save") {
          if store.save(draft) {
            draft = store.settings
            appModel.applySettings()
          }
        }
        .keyboardShortcut(.defaultAction)
      }

      if let validationMessage = store.validationMessage {
        Text(validationMessage)
          .foregroundStyle(.red)
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear { draft = store.settings }
  }

  private var trimmedNewBundleID: String {
    newOverrideBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func addOverride() {
    let bundleID = trimmedNewBundleID
    guard !bundleID.isEmpty else {
      return
    }
    draft.styleOverrides[bundleID] = newOverrideTone
    newOverrideBundleID = ""
  }
}
