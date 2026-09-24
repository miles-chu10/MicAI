import AppKit
import MicAICore
import SwiftUI

/// Everything MicAI has typed for you, with the ability to copy it again or
/// correct it — where correcting also teaches the vocabulary.
struct HistoryView: View {
  @ObservedObject var appModel: AppModel
  @State private var query = ""
  @State private var selection: HistoryEntry.ID?
  @State private var editedText = ""
  @State private var didCopy = false

  var body: some View {
    NavigationSplitView {
      List(filteredEntries, selection: $selection) { entry in
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.preview)
            .lineLimit(2)
          HStack(spacing: 6) {
            Text(entry.createdAt, format: .dateTime.hour().minute().month().day())
            if let applicationName = entry.applicationName {
              Text("· \(applicationName)")
            }
            if let tone = entry.tone {
              Text("· \(tone.displayName)")
            }
            if entry.mode == .command {
              Image(systemName: "wand.and.stars")
                .accessibilityLabel("AI Command")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .tag(entry.id)
      }
      .searchable(text: $query, prompt: "Search history")
      .frame(minWidth: 260)
    } detail: {
      if let entry = selectedEntry {
        detail(for: entry)
      } else {
        ContentUnavailableView(
          appModel.historyEntries.isEmpty ? "No history yet" : "Nothing selected",
          systemImage: "clock.arrow.circlepath",
          description: Text(
            appModel.historyEntries.isEmpty
              ? "Dictations you make will appear here."
              : "Pick an entry to read, copy, or correct it."
          )
        )
      }
    }
    .navigationTitle("History")
    .frame(minWidth: 720, minHeight: 440)
    // Re-seed the editor whenever the selection moves, so edits are never
    // carried from one entry onto another.
    .onChange(of: selection) { _, _ in
      editedText = selectedEntry?.finalText ?? ""
      didCopy = false
    }
  }

  @ViewBuilder
  private func detail(for entry: HistoryEntry) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      TextEditor(text: $editedText)
        .font(.body)
        .frame(minHeight: 160)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(.separator)
        }

      if entry.refined, entry.rawTranscript != entry.finalText {
        DisclosureGroup("What you said") {
          Text(entry.rawTranscript)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      HStack {
        Button(didCopy ? "Copied" : "Copy") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(editedText, forType: .string)
          didCopy = true
        }

        Button("Save Correction") {
          appModel.correctHistoryEntry(id: entry.id, to: editedText)
        }
        .disabled(editedText == entry.finalText)
        .help("Saves the fix and teaches MicAI any terms it got wrong.")

        Spacer()

        Button("Delete", role: .destructive) {
          appModel.deleteHistoryEntry(id: entry.id)
          selection = nil
        }
      }

      Text(footnote(for: entry))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .onAppear { editedText = entry.finalText }
  }

  private func footnote(for entry: HistoryEntry) -> String {
    var parts: [String] = [entry.mode == .command ? "AI Command" : "Dictation"]
    if entry.audioDuration > 0 {
      parts.append(String(format: "%.1fs of audio", entry.audioDuration))
    }
    parts.append(entry.refined ? "AI clean-up applied" : "Raw transcript")
    return parts.joined(separator: " · ")
  }

  private var selectedEntry: HistoryEntry? {
    appModel.historyEntries.first { $0.id == selection }
  }

  private var filteredEntries: [HistoryEntry] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      return appModel.historyEntries
    }
    return appModel.historyEntries.filter { entry in
      entry.finalText.localizedCaseInsensitiveContains(trimmedQuery)
        || entry.rawTranscript.localizedCaseInsensitiveContains(trimmedQuery)
        || (entry.applicationName?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
    }
  }
}
