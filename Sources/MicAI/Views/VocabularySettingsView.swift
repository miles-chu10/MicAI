import MicAICore
import SwiftUI

/// The learned-corrections list: names, jargon, and spellings MicAI gets wrong
/// once and then remembers.
struct VocabularySettingsView: View {
  @ObservedObject var appModel: AppModel
  @State private var heard = ""
  @State private var written = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Corrections")
        .font(.headline)
      Text(
        "When MicAI mishears a name or term, add it here — or just fix it in "
          + "History and MicAI will learn it. Corrections are applied on this "
          + "Mac before anything is sent anywhere."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        TextField("Heard as", text: $heard, prompt: Text("paraquet"))
        Image(systemName: "arrow.right")
          .foregroundStyle(.secondary)
        TextField("Written as", text: $written, prompt: Text("Parakeet"))
        Button("Add", action: add)
          .disabled(!isAddable)
      }

      if appModel.vocabularyEntries.isEmpty {
        ContentUnavailableView(
          "No corrections yet",
          systemImage: "character.book.closed",
          description: Text("Add a term above, or correct a line in History.")
        )
        .frame(maxHeight: .infinity)
      } else {
        Table(sortedEntries) {
          TableColumn("Heard as", value: \.heard)
          TableColumn("Written as", value: \.written)
          TableColumn("Uses") { entry in
            Text("\(entry.hitCount)")
              .monospacedDigit()
          }
          .width(50)
          TableColumn("") { entry in
            Button {
              appModel.deleteVocabularyEntry(id: entry.id)
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(entry.heard)")
          }
          .width(30)
        }
      }
    }
    .padding()
  }

  /// Most-used first: the entries earning their place are the ones worth
  /// seeing, and stale ones sink to where they are easy to prune.
  private var sortedEntries: [VocabularyEntry] {
    appModel.vocabularyEntries.sorted {
      if $0.hitCount != $1.hitCount {
        return $0.hitCount > $1.hitCount
      }
      return $0.heard.localizedCaseInsensitiveCompare($1.heard) == .orderedAscending
    }
  }

  private var isAddable: Bool {
    VocabularyEntry(heard: heard, written: written).isUsable
  }

  private func add() {
    guard isAddable else {
      return
    }
    appModel.upsertVocabularyEntry(
      heard: heard.trimmingCharacters(in: .whitespacesAndNewlines),
      written: written.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    heard = ""
    written = ""
  }
}
