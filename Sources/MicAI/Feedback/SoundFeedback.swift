import AppKit

/// Short system sounds for start, finish and failure, so you know MicAI heard
/// the key without looking for the HUD.
///
/// Uses the sounds that ship with macOS rather than bundled audio: they match
/// the rest of the system and follow the user's alert volume.
@MainActor
enum SoundFeedback {
  static func started() {
    NSSound(named: "Tink")?.play()
  }

  static func finished() {
    NSSound(named: "Pop")?.play()
  }

  static func failed() {
    NSSound(named: "Funk")?.play()
  }
}
