import MicAICore
import SwiftUI

/// Saved text you insert by saying its trigger phrase.
struct SnippetsSettingsPane: View {
  @ObservedObject var appModel: AppModel
  @State private var trigger = ""
  @State private var text = ""

  var body: some View {
    Form {
      Section {
        TextField("When I say", text: $trigger, prompt: Text("my email signature"))
        LabeledContent("Insert") {
          TextEditor(text: $text)
            .font(.body)
            .frame(minHeight: 70)
            .accessibilityLabel("Text to insert")
        }
        HStack {
          Spacer()
          Button("Add Snippet", action: add)
            .disabled(!Snippet(trigger: trigger, text: text).isUsable)
        }
      } header: {
        Text("New snippet")
      } footer: {
        Text(
          "Say the phrase on its own, as a whole dictation. MicAI doesn’t expand a phrase in the "
            + "middle of a sentence, so everyday speech never turns into a snippet by accident. "
            + "Snippets go in exactly as written and never go to the model."
        )
      }

      Section("Your snippets") {
        if appModel.snippetEntries.isEmpty {
          Text("No snippets yet.")
            .foregroundStyle(.secondary)
        }
        ForEach(appModel.snippetEntries) { snippet in
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
              Text("“\(snippet.trigger)”")
                .fontWeight(.medium)
              Text(snippet.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer()
            Text("\(snippet.useCount)")
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .help("Times used")
            Button {
              appModel.deleteSnippet(id: snippet.id)
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(snippet.trigger)")
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func add() {
    appModel.upsertSnippet(trigger: trigger, text: text)
    trigger = ""
    text = ""
  }
}
