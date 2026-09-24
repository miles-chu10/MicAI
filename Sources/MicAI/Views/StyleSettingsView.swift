import AppKit
import MicAICore
import SwiftUI

/// What happens to a transcript between the recognizer and the cursor.
struct StyleSettingsPane: View {
  @ObservedObject var appModel: AppModel
  @Binding var draft: AppSettings
  @State private var newOverrideBundleID = ""
  @State private var newOverrideTone: StyleTone = .casual

  var body: some View {
    Form {
      Section {
        Toggle("Polish dictation with AI", isOn: $draft.refinementEnabled)
        if draft.privacyMode {
          Label("Privacy mode is on, so clean-up is paused.", systemImage: "hand.raised.fill")
            .foregroundStyle(.orange)
        } else if draft.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Label("Choose a model in General to turn clean-up on.", systemImage: "info.circle")
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Clean-up")
      } footer: {
        Text(
          "Removes filler words and false starts, and writes in the register of the app you’re "
            + "typing into. If the model can’t be reached, your words go in as spoken."
        )
      }

      Section {
        Picker("When MicAI doesn’t recognise the app", selection: $draft.defaultTone) {
          ForEach(StyleTone.allCases, id: \.self) { tone in
            Text(tone.displayName).tag(tone)
          }
        }
      } header: {
        Text("Tone")
      } footer: {
        Text(
          "Slack and Messages get a casual tone, Mail and Outlook a professional one, and code "
            + "editors and terminals a technical one. \(draft.defaultTone.shortDescription)"
        )
      }

      Section {
        TextEditor(text: $draft.customInstructions)
          .font(.body)
          .frame(minHeight: 60)
          .accessibilityLabel("Your rules")
      } header: {
        Text("Your rules")
      } footer: {
        Text(
          "Standing instructions for every clean-up, such as “Use British spelling” or “Never use "
            + "exclamation marks”."
        )
      }

      Section("Per-app overrides") {
        if draft.styleOverrides.isEmpty {
          Text("No overrides. Add one when MicAI picks the wrong tone for an app.")
            .foregroundStyle(.secondary)
        }
        ForEach(draft.styleOverrides.keys.sorted(), id: \.self) { bundleID in
          HStack(spacing: 10) {
            AppBadge(bundleIdentifier: bundleID)
            Spacer()
            Picker(
              "Tone",
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
            .fixedSize()
            Button {
              draft.styleOverrides.removeValue(forKey: bundleID)
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove override")
          }
        }
        HStack {
          TextField("App", text: $newOverrideBundleID, prompt: Text("com.example.app"))
            .labelsHidden()
          Picker("Tone", selection: $newOverrideTone) {
            ForEach(StyleTone.allCases, id: \.self) { tone in
              Text(tone.displayName).tag(tone)
            }
          }
          .labelsHidden()
          .fixedSize()
          Button("Add", action: addOverride)
            .disabled(trimmedNewBundleID.isEmpty)
        }
        if let lastBundleID = appModel.historyEntries.first?.bundleIdentifier,
          draft.styleOverrides[lastBundleID] == nil
        {
          Button("Use the last app you dictated into") {
            newOverrideBundleID = lastBundleID
          }
          .buttonStyle(.link)
        }
      }

      Section("How each tone reads") {
        LabeledContent("You said") {
          Text("um so the build is uh broken again can you look")
            .italic()
            .foregroundStyle(.secondary)
        }
        ForEach(StyleTone.allCases, id: \.self) { tone in
          LabeledContent(tone.displayName) {
            Text(Self.example(for: tone))
          }
        }
      }
    }
    .formStyle(.grouped)
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

  /// Illustrations of each register, not model output.
  private static func example(for tone: StyleTone) -> String {
    switch tone {
    case .casual:
      "build’s broken again, can you take a look?"
    case .professional:
      "The build is failing again. Could you take a look?"
    case .technical:
      "Build is failing again. Can you investigate?"
    case .neutral:
      "The build is broken again. Can you look?"
    }
  }
}

/// An app's icon and name, looked up from its bundle identifier, falling back
/// to the identifier itself for apps that are not installed.
struct AppBadge: View {
  let bundleIdentifier: String

  var body: some View {
    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    HStack(spacing: 8) {
      if let url {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
          .resizable()
          .frame(width: 20, height: 20)
          .accessibilityHidden(true)
      } else {
        Image(systemName: "app.dashed")
          .frame(width: 20, height: 20)
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleIdentifier)
        if url != nil {
          Text(bundleIdentifier)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
