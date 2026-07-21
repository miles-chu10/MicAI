import Combine
import Foundation
import MicAICore

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var modelState: ModelPreparationState = .notDownloaded
  @Published private(set) var operationPhase: OperationPhase = .idle
  @Published private(set) var inputLevel: Float = 0
  @Published private(set) var lastTranscript: String?
  @Published private(set) var errorMessage: String?

  let settingsStore: SettingsStore
  let microphonePermission: MicrophonePermissionService
  let accessibilityPermission: AccessibilityPermissionService

  private let coordinator: OperationCoordinator
  private let recognizer: FluidAudioRecognizer
  private let pipeline: DictationPipeline
  private let targetTracker: TargetApplicationTracker
  private let insertionCoordinator: TextInsertionCoordinator
  private var operationID: UUID?
  private var operationTarget: TargetIdentity?

  private lazy var hotkeyMonitor = GlobalHotkeyMonitor(
    settings: settingsStore.settings
  ) { [weak self] mode, action in
    self?.handleHotkey(mode: mode, action: action)
  }

  init() {
    let settingsStore = SettingsStore()
    let coordinator = OperationCoordinator()
    let recognizer = FluidAudioRecognizer()
    let targetTracker = TargetApplicationTracker()

    self.settingsStore = settingsStore
    microphonePermission = MicrophonePermissionService()
    accessibilityPermission = AccessibilityPermissionService()
    self.coordinator = coordinator
    self.recognizer = recognizer
    self.targetTracker = targetTracker
    pipeline = DictationPipeline(
      audioCapture: AVAudioEngineCapture(),
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: coordinator
    )
    insertionCoordinator = TextInsertionCoordinator(
      pasteboard: SystemPasteboardAdapter(),
      keyboard: CGEventKeyboardSynthesizer(),
      targetValidator: targetTracker
    )

    Task { @MainActor [weak self] in
      self?.hotkeyMonitor.start()
    }
  }

  func prepareModel() {
    errorMessage = nil
    let recognizer = self.recognizer
    let appModel = self
    Task {
      do {
        try await recognizer.prepare { state in
          Task { @MainActor in
            appModel.modelState = state
          }
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  func requestMicrophonePermission() {
    Task {
      _ = await microphonePermission.request()
    }
  }

  func requestAccessibilityPermission() {
    accessibilityPermission.requestPrompt()
  }

  func applySettings() {
    hotkeyMonitor.update(settings: settingsStore.settings)
  }

  private func handleHotkey(mode: MicAIMode, action: HotkeyAction) {
    guard mode == .dictation else {
      hotkeyMonitor.reset(mode: .command)
      errorMessage = "AI Commands are not available yet."
      return
    }
    Task {
      switch action {
      case .startRecording:
        await startDictation()
      case .stopRecording:
        await finishDictation()
      case .cancelRecording:
        await cancelDictation()
      }
    }
  }

  private func startDictation() async {
    guard operationID == nil else {
      return
    }
    guard modelState == .ready else {
      rejectDictationStart(with: .asrNotInitialized)
      return
    }

    microphonePermission.refresh()
    guard microphonePermission.isGranted else {
      rejectDictationStart(with: .microphoneDenied)
      return
    }
    accessibilityPermission.refresh()
    guard accessibilityPermission.isTrusted else {
      rejectDictationStart(with: .accessibilityDenied)
      return
    }
    guard let target = await targetTracker.capture() else {
      rejectDictationStart(with: .targetChanged)
      return
    }

    do {
      errorMessage = nil
      lastTranscript = nil
      let appModel = self
      _ = try await pipeline.begin(
        target: target,
        levels: { level in
          Task { @MainActor in
            appModel.inputLevel = level
          }
        },
        operationStarted: { operationID in
          await MainActor.run {
            appModel.operationID = operationID
            appModel.operationTarget = target
            appModel.operationPhase = .recording
          }
        }
      )
    } catch {
      if error as? MicAIError == .cancelled {
        hotkeyMonitor.reset(mode: .dictation)
        return
      }
      errorMessage = error.localizedDescription
      operationPhase = .failed((error as? MicAIError) ?? .audioUnavailable)
      clearOperation()
      hotkeyMonitor.reset(mode: .dictation)
    }
  }

  private func finishDictation() async {
    guard let operationID, let target = operationTarget else {
      return
    }

    operationPhase = .transcribing
    inputLevel = 0
    do {
      let transcript = try await pipeline.finish(operationID: operationID)
      guard await coordinator.markInserting(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      operationPhase = .inserting
      accessibilityPermission.refresh()
      guard accessibilityPermission.isTrusted else {
        throw MicAIError.accessibilityDenied
      }

      do {
        try await insertionCoordinator.apply(.insert(transcript.text), to: target)
      } catch let error as MicAIError where error == .clipboardChanged {
        _ = await coordinator.complete(operationID: operationID)
        complete(transcript: transcript, diagnostic: error.localizedDescription)
        return
      }

      guard await coordinator.complete(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      complete(transcript: transcript)
    } catch {
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      if await coordinator.isCurrent(operationID: operationID) {
        _ = await coordinator.fail(operationID: operationID, error: micAIError)
      }
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
      clearOperation()
    }
  }

  private func cancelDictation() async {
    guard let operationID else {
      return
    }
    await pipeline.cancel(operationID: operationID)
    operationPhase = .idle
    errorMessage = nil
    inputLevel = 0
    clearOperation()
  }

  private func complete(transcript: Transcript, diagnostic: String? = nil) {
    lastTranscript = transcript.text
    errorMessage = diagnostic
    operationPhase = .idle
    clearOperation()
  }

  private func clearOperation() {
    operationID = nil
    operationTarget = nil
  }

  private func rejectDictationStart(with error: MicAIError) {
    errorMessage = error.localizedDescription
    hotkeyMonitor.reset(mode: .dictation)
  }
}
