import Foundation

/// Where a custom mode's result goes.
public enum CustomModeOutput: String, Codable, CaseIterable, Sendable {
  /// Replaces the selection when there is one, otherwise types at the cursor.
  case insert
  /// Opens in the answer window and changes nothing in your document.
  case window

  public var displayName: String {
    switch self {
    case .insert:
      "Replace the selection, or type at the cursor"
    case .window:
      "Show in a window"
    }
  }
}

/// A mode you define: a name, standing instructions for the model, and its own
/// shortcut. Command, Translate and Ask AI are fixed examples of the same idea;
/// this lets you add "reply to this email", "make bullet points" or "turn this
/// into a prompt for a coding agent" without waiting for a release.
public struct CustomMode: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public var name: String
  /// What the model should do with what you say and, when present, the
  /// selected text.
  public var instructions: String
  public var hotkey: Hotkey?
  public var output: CustomModeOutput

  public init(
    id: UUID = UUID(),
    name: String,
    instructions: String,
    hotkey: Hotkey? = nil,
    output: CustomModeOutput = .insert
  ) {
    self.id = id
    self.name = name
    self.instructions = instructions
    self.hotkey = hotkey
    self.output = output
  }

  /// A mode with no name cannot be told apart in the HUD or History, and one
  /// with no instructions would send the model nothing to act on.
  public var isComplete: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Starting points offered in Settings. Each is ordinary, editable text.
  public static let templates: [CustomMode] = [
    CustomMode(
      name: "Email reply",
      instructions:
        "Write a reply email that says what I said. If an email is selected, reply to "
        + "it and match its tone. Include a short greeting and sign-off."
    ),
    CustomMode(
      name: "Bullet points",
      instructions:
        "Turn what I said, or the selected text if there is some, into a concise "
        + "bulleted list. Keep my wording where possible."
    ),
    CustomMode(
      name: "Coding prompt",
      instructions:
        "Turn what I said into a clear prompt for an AI coding agent: the goal, the "
        + "constraints, the files involved and how to tell it is done. Keep file paths, "
        + "commands and identifiers exactly as spoken."
    ),
  ]
}
