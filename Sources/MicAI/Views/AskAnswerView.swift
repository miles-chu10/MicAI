import AppKit
import MicAICore
import SwiftUI

/// An Ask AI answer that was a question rather than content to type.
struct AskAnswer: Identifiable, Equatable {
  let id = UUID()
  let question: String
  let answer: String
  let usedSelection: Bool
  /// Set when a custom mode produced this rather than Ask AI.
  var modeName: String?
}

/// Shows an answer for reading rather than pasting it into whatever had focus.
///
/// Copy rather than "Insert at cursor": by the time this window is open it owns
/// the focus, so inserting would mean reactivating the previous app and
/// synthesising a paste into a target the user may already have moved away
/// from. Copy always does what it says.
struct AskAnswerView: View {
  @ObservedObject var appModel: AppModel
  @State private var didCopy = false

  var body: some View {
    Group {
      if let answer = appModel.pendingAnswer {
        content(for: answer)
      } else {
        ContentUnavailableView {
          Label("No answer yet", systemImage: MicAIMode.ask.symbol)
        } description: {
          if let hotkey = appModel.settingsStore.settings.askHotkey {
            Text("Hold \(hotkey.displayName) and ask a question.")
          } else {
            Text("Turn on the Ask AI shortcut in Settings.")
          }
        }
      }
    }
    .frame(minWidth: 480, minHeight: 360)
    .navigationTitle(appModel.pendingAnswer?.modeName ?? "Ask AI")
  }

  @ViewBuilder
  private func content(for answer: AskAnswer) -> some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(answer.modeName.map { "\($0) · you said" } ?? "You asked")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(answer.question)
              .font(.title3.weight(.semibold))
          }

          if answer.usedSelection {
            Label("Your selection was used as context", systemImage: "text.viewfinder")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Text(answer.answer)
            .font(.body)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .textSelection(.enabled)
      }

      Divider()

      HStack(spacing: 8) {
        Label(footnote(for: answer), systemImage: MicAIMode.ask.symbol)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Dismiss") {
          appModel.pendingAnswer = nil
          didCopy = false
        }
        .keyboardShortcut(.cancelAction)
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(answer.answer, forType: .string)
          didCopy = true
        } label: {
          Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
        }
        .keyboardShortcut("c", modifiers: .command)
        .buttonStyle(.borderedProminent)
        .tint(MicAIMode.ask.tint)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(.bar)
    }
    // A new answer must not leave the previous answer's "Copied" state showing.
    .onChange(of: answer.id) { _, _ in
      didCopy = false
    }
  }

  private func footnote(for answer: AskAnswer) -> String {
    answer.usedSelection
      ? "Your selection wasn’t changed." : "Answered by \(appModel.providerName)"
  }
}
