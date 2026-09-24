import Foundation
import MicAICore
import Testing

@Suite
struct CommandPipelineTests {
  @Test
  func snapshotsModelWhenCommandStarts() async throws {
    let audio = CommandPipelineAudioCapture()
    let recognizer = CommandPipelineSpeechRecognizer()
    let coordinator = OperationCoordinator()
    let executor = CapturingCommandExecutor()
    let insertion = TextInsertionCoordinator(
      pasteboard: CommandPipelinePasteboard(),
      keyboard: CommandPipelineKeyboard(),
      targetValidator: CommandPipelineTargetValidator(),
      delay: {}
    )
    let pipeline = CommandPipeline(
      dictationPipeline: DictationPipeline(
        audioCapture: audio,
        recognizer: recognizer,
        cleaner: TranscriptCleaner(),
        coordinator: coordinator
      ),
      commandEngine: executor,
      insertionCoordinator: insertion,
      coordinator: coordinator
    )

    let operationID = try await pipeline.begin(
      target: TargetIdentity(processIdentifier: 42),
      model: "model-at-start",
      levels: { _ in }
    )
    _ = try await pipeline.finish(operationID: operationID)

    #expect(await executor.receivedModel == "model-at-start")
  }
}

private actor CommandPipelineAudioCapture: AudioCapturing {
  func start(levels: @escaping @Sendable (Float) -> Void) async throws {}

  func stop() async throws -> RecordedAudio {
    RecordedAudio(
      samples: [Float](repeating: 0.1, count: 8_000),
      sampleRate: 16_000,
      duration: .milliseconds(500)
    )
  }

  func cancel() async {}
}

private actor CommandPipelineSpeechRecognizer: SpeechRecognizing {
  func prepare(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws {
    progress(.ready)
  }

  func transcribe(samples: [Float]) async throws -> Transcript {
    Transcript(
      text: "draft a reply",
      audioDuration: 0.5,
      processingDuration: 0.1,
      confidence: 0.9
    )
  }
}

private actor CapturingCommandExecutor: CommandExecuting {
  private(set) var receivedModel: String?

  func execute(
    instruction: String,
    selectedText: String?,
    model: String
  ) async throws -> InsertionIntent {
    receivedModel = model
    return .insert("done")
  }
}

private final class CommandPipelinePasteboard: PasteboardAccessing, @unchecked Sendable {
  func snapshot() throws -> PasteboardSnapshot {
    PasteboardSnapshot(items: [], changeCount: 1)
  }

  func writePlainText(_ text: String) throws -> Int { 2 }
  func restore(_ snapshot: PasteboardSnapshot) throws {}
  func currentChangeCount() -> Int { 1 }
}

private struct CommandPipelineKeyboard: KeyboardSynthesizing, Sendable {
  func copy() throws {}
  func paste() throws {}
}

private struct CommandPipelineTargetValidator: TargetValidating, Sendable {
  func isCurrent(_ target: TargetIdentity) async -> Bool { true }
}
