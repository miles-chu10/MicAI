import MicAICore
import SwiftUI

/// Your own modes: a name, instructions, a shortcut, and where the result goes.
struct CustomModesSettingsPane: View {
  @ObservedObject var appModel: AppModel
  @Binding var draft: AppSettings

  var body: some View {
    Form {
      if draft.customModes.isEmpty {
        Section {
          Text("No custom modes yet. Start from a template or a blank mode below.")
            .foregroundStyle(.secondary)
        } footer: {
          Text(
            "A custom mode is like Command with standing instructions: hold its shortcut, "
              + "speak, and the model follows your instructions on what you said and on any "
              + "selected text."
          )
        }
      }

      ForEach($draft.customModes) { $mode in
        Section {
          TextField("Name", text: $mode.name, prompt: Text("Email reply"))
          LabeledContent("Instructions") {
            TextEditor(text: $mode.instructions)
              .font(.body)
              .frame(minHeight: 64)
              .accessibilityLabel("Instructions for \(mode.name)")
          }
          LabeledContent("Shortcut") {
            ShortcutRecorder(hotkey: $mode.hotkey)
          }
          Picker("Result", selection: $mode.output) {
            ForEach(CustomModeOutput.allCases, id: \.self) { output in
              Text(output.displayName).tag(output)
            }
          }
          Button("Delete Mode", role: .destructive) {
            draft.customModes.removeAll { $0.id == mode.id }
          }
        } header: {
          HStack(spacing: 6) {
            ModeDot(mode: .custom)
            Text(mode.name.isEmpty ? "Untitled mode" : mode.name)
          }
        }
      }

      Section {
        Menu("Add Mode") {
          Button("Blank Mode") {
            draft.customModes.append(CustomMode(name: "", instructions: ""))
          }
          Divider()
          ForEach(CustomMode.templates) { template in
            Button(template.name) {
              draft.customModes.append(
                CustomMode(
                  name: template.name,
                  instructions: template.instructions,
                  output: template.output
                )
              )
            }
          }
        }
        .fixedSize()
      } footer: {
        Text(footer)
      }
    }
    .formStyle(.grouped)
  }

  private var footer: String {
    if draft.privacyMode {
      return "Custom modes use your language model, so they are paused in privacy mode."
    }
    return "Custom modes use your language model and send what you said, plus any selected "
      + "text. Shortcuts need Control, Option or Command, and must differ from every other mode."
  }
}
