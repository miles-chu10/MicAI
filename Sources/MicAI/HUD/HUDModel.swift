import Combine
import Foundation
import MicAICore

/// Everything the HUD shows, pushed from `AppModel` and observed by the view.
///
/// Kept separate from `AppModel` so the panel redraws on HUD changes only, not
/// on every settings or history update the app model also publishes.
@MainActor
final class HUDModel: ObservableObject {
  /// How many recent input levels the waveform draws.
  static let levelCount = 18

  @Published var phase: OperationPhase = .idle {
    didSet {
      if phase == .recording, oldValue != .recording {
        recordingStartedAt = Date()
        levels = Array(repeating: 0, count: Self.levelCount)
      }
    }
  }
  @Published var mode: MicAIMode = .dictation
  @Published var message: String?
  /// A short qualifier: "Hands-free", "to Spanish", "Casual, for Slack".
  @Published var detail: String?
  /// Whether the current step runs on this Mac or has gone to the model.
  @Published var providerName = "ChatGPT"
  @Published var isHandsFree = false
  @Published private(set) var levels: [Float] = Array(repeating: 0, count: levelCount)
  @Published private(set) var recordingStartedAt = Date()

  func push(level: Float) {
    guard phase == .recording else {
      return
    }
    var next = levels
    next.removeFirst()
    next.append(level)
    levels = next
  }
}
