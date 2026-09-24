import AppKit
import SwiftUI

/// An Ask AI answer that was a question rather than content to type.
struct AskAnswer: Identifiable, Equatable {
  let id = UUID()
  let question: String
  let answer: String
  let usedSelection: Bool
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
        ContentUnavailableView(
          "No answer yet",
          systemImage: "bubble.left.and.text.bubble.right",
          description: Text("Hold the Ask AI hotkey and ask a question.")
        )
      }
    }
    .frame(minWidth: 460, minHeight: 320)
    .navigationTitle("Ask AI")
  }

  @ViewBuilder
  private func content(for answer: AskAnswer) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text("You asked")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(answer.question)
          .font(.headline)
          .textSelection(.enabled)
      }

      if answer.usedSelection {
        Label("Answered using your selection as context", systemImage: "text.viewfinder")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      ScrollView {
        Text(answer.answer)
          .font(.body)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      MicAIActionCluster {
        HStack {
          Button(
            didCopy ? "Copied" : "Copy Answer",
            systemImage: didCopy ? "checkmark" : "doc.on.doc"
          ) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer.answer, forType: .string)
            didCopy = true
          }
          .micAIPrimaryButtonStyle()
          .keyboardShortcut("c", modifiers: .command)

          Spacer()

          Button("Dismiss") {
            appModel.pendingAnswer = nil
            didCopy = false
          }
          .micAISecondaryButtonStyle()
          .keyboardShortcut(.cancelAction)
        }
      }
    }
    .padding(18)
    // A new answer must not leave the previous answer's "Copied" state showing.
    .onChange(of: answer.id) { _, _ in
      didCopy = false
    }
  }
}
