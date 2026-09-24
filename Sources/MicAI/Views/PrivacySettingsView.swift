import MicAICore
import SwiftUI

/// Where your words go, and the switch that keeps them all on this Mac.
struct PrivacySettingsPane: View {
  @ObservedObject var appModel: AppModel
  @Binding var draft: AppSettings
  @State private var confirmingClear = false

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $draft.privacyMode) {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Privacy mode")
              Text("Keep everything on this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "hand.raised.fill")
          }
        }
      } footer: {
        Text(
          "Turns off clean-up, Command, Translate and Ask AI. Your settings come back exactly as "
            + "they were when you turn it off."
        )
      }

      Section("Where your words go") {
        LabeledContent {
          Text("Microphone, speech recognition, vocabulary, snippets, history, pasting")
            .multilineTextAlignment(.trailing)
        } label: {
          Label("Stays on this Mac", systemImage: "laptopcomputer")
        }
        LabeledContent {
          VStack(alignment: .trailing, spacing: 2) {
            Text("Clean-up, Command, Translate, Ask AI")
            Text("The transcript and any selected text. Never audio.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .multilineTextAlignment(.trailing)
        } label: {
          Label("Sent to \(appModel.providerName)", systemImage: "cloud")
        }
      }

      Section {
        Toggle("Keep a history of dictations", isOn: $draft.historyEnabled)
        Picker("Keep up to", selection: $draft.historyLimit) {
          ForEach(limitsIncludingCurrent, id: \.self) { limit in
            Text("\(limit) entries").tag(limit)
          }
        }
        .disabled(!draft.historyEnabled)
        LabeledContent("Saved now", value: "\(appModel.historyEntries.count)")
        Button("Clear History…", role: .destructive) {
          confirmingClear = true
        }
        .disabled(appModel.historyEntries.isEmpty)
      } header: {
        Text("History")
      } footer: {
        Text("Stored on this Mac only, in Application Support. Never uploaded.")
      }
    }
    .formStyle(.grouped)
    .confirmationDialog(
      "Clear all history?",
      isPresented: $confirmingClear,
      titleVisibility: .visible
    ) {
      Button("Clear History", role: .destructive) {
        appModel.clearHistory()
      }
    } message: {
      Text("This can’t be undone. Learned vocabulary and snippets are kept.")
    }
  }

  /// Includes whatever the current limit is, so a value set by an earlier
  /// build still shows as selected.
  private var limitsIncludingCurrent: [Int] {
    Array(Set(Self.limits + [draft.historyLimit])).sorted()
  }

  private static let limits = [50, 200, 500, 1_000, 2_000]
}
