import MicAICore
import SwiftUI

/// Corrections applied on this Mac before anything reaches the model.
struct VocabularySettingsPane: View {
  @ObservedObject var appModel: AppModel
  @State private var heard = ""
  @State private var written = ""

  var body: some View {
    Form {
      Section {
        HStack(spacing: 8) {
          TextField("Heard as", text: $heard, prompt: Text("paraquet"))
          Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          TextField("Written as", text: $written, prompt: Text("Parakeet"))
          Button("Add", action: add)
            .disabled(!canAdd)
        }
      } header: {
        Text("Add a correction")
      } footer: {
        Text("Correcting a line in History also adds its changed names here.")
      }

      Section {
        if appModel.vocabularyEntries.isEmpty {
          Text("No corrections yet.")
            .foregroundStyle(.secondary)
        }
        ForEach(sortedEntries) { entry in
          HStack(spacing: 10) {
            Text(entry.heard)
              .foregroundStyle(.secondary)
              .frame(width: 170, alignment: .leading)
            Text(entry.written)
              .fontWeight(.medium)
            Spacer()
            Text("\(entry.hitCount)")
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .help("Times this correction was applied")
            Button {
              appModel.deleteVocabularyEntry(id: entry.id)
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(entry.heard)")
          }
        }
      } header: {
        Text("Corrections")
      } footer: {
        Text(
          "Applied on this Mac before anything reaches the model, so names come out right even in "
            + "privacy mode."
        )
      }
    }
    .formStyle(.grouped)
  }

  private var sortedEntries: [VocabularyEntry] {
    appModel.vocabularyEntries.sorted { $0.hitCount > $1.hitCount }
  }

  private var canAdd: Bool {
    VocabularyEntry(heard: heard, written: written).isUsable
  }

  private func add() {
    appModel.upsertVocabularyEntry(heard: heard, written: written)
    heard = ""
    written = ""
  }
}
