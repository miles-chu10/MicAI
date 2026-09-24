import AppKit
import MicAICore
import SwiftUI

/// Everything MicAI has typed for you, with the ability to copy it again or
/// correct it — where correcting also teaches the vocabulary.
struct HistoryView: View {
  @ObservedObject var appModel: AppModel
  @State private var query = ""
  @State private var modeFilter: MicAIMode?
  @State private var selection: HistoryEntry.ID?
  @State private var editedText = ""
  @State private var didCopy = false

  var body: some View {
    NavigationSplitView {
      List(filteredEntries, selection: $selection) { entry in
        HistoryRow(entry: entry)
          .tag(entry.id)
      }
      .safeAreaInset(edge: .top, spacing: 0) {
        UsageSummary(stats: appModel.usage(since: Self.weekStart))
      }
      .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
      .overlay {
        if filteredEntries.isEmpty {
          ContentUnavailableView(
            appModel.historyEntries.isEmpty ? "No history yet" : "No matches",
            systemImage: "clock.arrow.circlepath",
            description: Text(
              appModel.historyEntries.isEmpty
                ? "What you dictate will appear here."
                : "Try another search or mode."
            )
          )
        }
      }
    } detail: {
      if let entry = selectedEntry {
        detail(for: entry)
      } else {
        ContentUnavailableView(
          "Nothing selected",
          systemImage: "text.cursor",
          description: Text("Pick an entry to read, copy or correct it.")
        )
      }
    }
    .searchable(text: $query, placement: .sidebar, prompt: "Search")
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Mode", selection: $modeFilter) {
          Text("All").tag(MicAIMode?.none)
          ForEach(MicAIMode.allCases, id: \.self) { mode in
            Text(mode.shortName).tag(MicAIMode?.some(mode))
          }
        }
        .pickerStyle(.segmented)
        .fixedSize()
      }
    }
    .navigationTitle("History")
    .frame(minWidth: 820, minHeight: 500)
    // Re-seed the editor whenever the selection moves, so edits are never
    // carried from one entry onto another.
    .onChange(of: selection) { _, _ in
      editedText = selectedEntry?.finalText ?? ""
      didCopy = false
    }
  }

  @ViewBuilder
  private func detail(for entry: HistoryEntry) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 8) {
          ModeDot(mode: entry.mode)
          Text(entry.mode.shortName)
            .fontWeight(.semibold)
          Text(metadata(for: entry))
            .foregroundStyle(.secondary)
        }
        .font(.callout)

        if entry.rawTranscript != entry.finalText {
          block("Heard") {
            Text(entry.rawTranscript)
              .foregroundStyle(.secondary)
          }
        }

        block(entry.mode == .ask ? "Answer" : "Inserted") {
          Text(entry.finalText)
            .font(.title3)
        }

        block("Correct it") {
          TextEditor(text: $editedText)
            .font(.body)
            .frame(minHeight: 90)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(.background, in: .rect(cornerRadius: 8))
            .overlay {
              RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
            }
            .accessibilityLabel("Corrected text")
          Text("Changed names are added to Vocabulary, so MicAI gets them right next time.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        HStack {
          Button("Delete", role: .destructive) {
            appModel.deleteHistoryEntry(id: entry.id)
            selection = nil
          }
          Spacer()
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(editedText, forType: .string)
            didCopy = true
          } label: {
            Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
          }
          Button("Save Correction") {
            appModel.correctHistoryEntry(id: entry.id, to: editedText)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(editedText == entry.finalText)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
    }
    .onAppear { editedText = entry.finalText }
  }

  private func block<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      content()
    }
  }

  private func metadata(for entry: HistoryEntry) -> String {
    var parts: [String] = []
    if let name = entry.applicationName {
      parts.append(name)
    }
    if let tone = entry.tone {
      parts.append(tone.displayName)
    }
    parts.append(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
    if entry.audioDuration > 0 {
      parts.append(String(format: "%.1fs of audio", entry.audioDuration))
    }
    return parts.joined(separator: " · ")
  }

  private var selectedEntry: HistoryEntry? {
    appModel.historyEntries.first { $0.id == selection }
  }

  private var filteredEntries: [HistoryEntry] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return appModel.historyEntries.filter { entry in
      if let modeFilter, entry.mode != modeFilter {
        return false
      }
      guard !trimmedQuery.isEmpty else {
        return true
      }
      return entry.finalText.localizedCaseInsensitiveContains(trimmedQuery)
        || entry.rawTranscript.localizedCaseInsensitiveContains(trimmedQuery)
        || (entry.applicationName?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
    }
  }

  static var weekStart: Date {
    Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
  }
}

private struct HistoryRow: View {
  let entry: HistoryEntry

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
      ModeDot(mode: entry.mode)
      VStack(alignment: .leading, spacing: 3) {
        Text(entry.preview)
          .lineLimit(2)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 3)
  }

  private var subtitle: String {
    var parts: [String] = []
    if let name = entry.applicationName {
      parts.append(name)
    }
    if let tone = entry.tone {
      parts.append(tone.displayName)
    }
    parts.append(entry.createdAt.formatted(.relative(presentation: .named)))
    return parts.joined(separator: " · ")
  }
}

/// This week's words, time saved and speaking rate, above the list.
struct UsageSummary: View {
  let stats: UsageStats

  var body: some View {
    HStack(spacing: 0) {
      figure("\(stats.wordCount.formatted())", "words this week")
      Divider().frame(height: 28)
      figure(minutes, "saved vs typing")
      Divider().frame(height: 28)
      figure(stats.wordsPerMinute.map { "\($0)" } ?? "–", "words a minute")
    }
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(.bar)
    .help("Compared with typing at 40 words a minute. Counted from your history on this Mac.")
  }

  private var minutes: String {
    let value = stats.minutesSaved
    if value == 0 {
      return "0 min"
    }
    return value < 1 ? "<1 min" : "\(Int(value.rounded())) min"
  }

  private func figure(_ value: String, _ label: String) -> some View {
    VStack(spacing: 1) {
      Text(value)
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .monospacedDigit()
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}
