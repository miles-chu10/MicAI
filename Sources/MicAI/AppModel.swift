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
  @Published private(set) var providerStatus: ProviderStatus = .notConfigured
  @Published var isOnboardingPresented = false

  let settingsStore: SettingsStore
  let microphonePermission: MicrophonePermissionService
  let accessibilityPermission: AccessibilityPermissionService
  let launchAtLogin: LaunchAtLoginService

  private let coordinator: OperationCoordinator
  private let recognizer: FluidAudioRecognizer
  private let pipeline: DictationPipeline
  private let commandPipeline: CommandPipeline
  private let targetTracker: TargetApplicationTracker
  private let insertionCoordinator: TextInsertionCoordinator
  private let hudController: RecordingHUDController
  private let providerStatusRelay: ProviderStatusRelay
  private var operationID: UUID?
  private var operationAttemptID: UUID?
  private var operationStartupMode: MicAIMode?
  private var pendingStopMode: MicAIMode?
  private var operationMode: MicAIMode?
  private var operationTarget: TargetIdentity?
  private var cancellables: Set<AnyCancellable> = []

  private lazy var hotkeyMonitor = GlobalHotkeyMonitor(
    settings: settingsStore.settings,
    actionHandler: { [weak self] mode, action in
      self?.handleHotkey(mode: mode, action: action)
    },
    cancelHandler: { [weak self] in
      self?.cancelCurrentOperation()
    }
  )

  init() {
    let settingsStore = SettingsStore()
    let coordinator = OperationCoordinator()
    let recognizer = FluidAudioRecognizer()
    let targetTracker = TargetApplicationTracker()
    let providerStatusRelay = ProviderStatusRelay()

    self.settingsStore = settingsStore
    microphonePermission = MicrophonePermissionService()
    accessibilityPermission = AccessibilityPermissionService()
    launchAtLogin = LaunchAtLoginService()
    hudController = RecordingHUDController()
    self.providerStatusRelay = providerStatusRelay
    self.coordinator = coordinator
    self.recognizer = recognizer
    self.targetTracker = targetTracker
    pipeline = DictationPipeline(
      audioCapture: AVAudioEngineCapture(),
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: coordinator
    )
    let insertionCoordinator = TextInsertionCoordinator(
      pasteboard: SystemPasteboardAdapter(),
      keyboard: CGEventKeyboardSynthesizer(),
      targetValidator: targetTracker
    )
    self.insertionCoordinator = insertionCoordinator
    commandPipeline = CommandPipeline(
      dictationPipeline: pipeline,
      commandEngine: CommandEngine(
        transformer: Self.makeTransformer(
          for: settingsStore.settings.llmProvider,
          statusHandler: providerStatusRelay.send
        )
      ),
      insertionCoordinator: insertionCoordinator,
      coordinator: coordinator
    )
    isOnboardingPresented = !settingsStore.hasSeenOnboarding
    let observedPublishers = [
      settingsStore.objectWillChange.eraseToAnyPublisher(),
      microphonePermission.objectWillChange.eraseToAnyPublisher(),
      accessibilityPermission.objectWillChange.eraseToAnyPublisher(),
      launchAtLogin.objectWillChange.eraseToAnyPublisher(),
    ]
    for publisher in observedPublishers {
      publisher
        .sink { [weak self] _ in
          Task { @MainActor in
            self?.objectWillChange.send()
          }
        }
        .store(in: &cancellables)
    }
    Publishers.CombineLatest3($operationPhase, $inputLevel, $errorMessage)
      .sink { [weak self] phase, level, message in
        self?.hudController.update(
          phase: phase,
          level: level,
          message: message
        )
      }
      .store(in: &cancellables)
    providerStatusRelay.setHandler { [weak self] status in
      Task { @MainActor [weak self] in
        self?.providerStatus = status
      }
    }

    Task { @MainActor [weak self] in
      self?.refreshSystemStatus()
      self?.refreshProviderStatus()
      self?.hotkeyMonitor.start()
      await self?.prepareCachedModelIfAvailable()
    }
  }

  var readiness: AppReadiness {
    AppReadiness(
      microphoneGranted: microphonePermission.isGranted,
      accessibilityGranted: accessibilityPermission.isTrusted,
      speechModelReady: modelState == .ready,
      commandHotkeyConfigured: settingsStore.settings.commandHotkey != nil,
      languageModelConfigured: !settingsStore.settings.llmModel
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      operationActive: operationID != nil || operationAttemptID != nil
    )
  }

  var isOperationActive: Bool {
    operationID != nil || operationAttemptID != nil
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

  private func prepareCachedModelIfAvailable() async {
    let recognizer = self.recognizer
    let appModel = self
    do {
      _ = try await recognizer.prepareCachedIfAvailable { state in
        Task { @MainActor in
          appModel.modelState = state
        }
      }
    } catch {
      errorMessage = error.localizedDescription
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
    let transformer = Self.makeTransformer(
      for: settingsStore.settings.llmProvider,
      statusHandler: providerStatusRelay.send
    )
    Task {
      await commandPipeline.updateTransformer(transformer)
    }
    refreshProviderStatus()
  }

  func refreshSystemStatus() {
    microphonePermission.refresh()
    accessibilityPermission.refresh()
    launchAtLogin.refresh()
  }

  func cancelCurrentOperation() {
    Task {
      await cancelActiveOperation()
    }
  }

  func stopRuntime() {
    hotkeyMonitor.stop()
    hudController.close()
    cancelCurrentOperation()
  }

  func showOnboarding() {
    isOnboardingPresented = true
  }

  func dismissOnboarding() {
    settingsStore.markOnboardingSeen()
    isOnboardingPresented = false
  }

  private func handleHotkey(mode: MicAIMode, action: HotkeyAction) {
    if action == .stopRecording, operationStartupMode == mode {
      pendingStopMode = mode
      return
    }

    Task {
      switch (mode, action) {
      case (.dictation, .startRecording):
        await startDictation()
      case (.dictation, .stopRecording):
        await finishDictation()
      case (.dictation, .cancelRecording):
        await cancelDictation()
      case (.command, .startRecording):
        await startCommand()
      case (.command, .stopRecording):
        await finishCommand()
      case (.command, .cancelRecording):
        await cancelCommand()
      }
    }
  }

  private func startDictation() async {
    guard operationID == nil, operationAttemptID == nil else {
      hotkeyMonitor.reset(mode: .dictation)
      return
    }
    let attemptID = UUID()
    operationAttemptID = attemptID
    operationStartupMode = .dictation
    guard modelState == .ready else {
      rejectDictationStart(with: .asrNotInitialized)
      clearOperation(ifAttemptID: attemptID)
      return
    }

    microphonePermission.refresh()
    guard microphonePermission.isGranted else {
      rejectDictationStart(with: .microphoneDenied)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    accessibilityPermission.refresh()
    guard accessibilityPermission.isTrusted else {
      rejectDictationStart(with: .accessibilityDenied)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    guard let target = await targetTracker.capture() else {
      rejectDictationStart(with: .targetChanged)
      clearOperation(ifAttemptID: attemptID)
      return
    }

    do {
      errorMessage = nil
      lastTranscript = nil
      let appModel = self
      let coordinator = self.coordinator
      _ = try await pipeline.begin(
        target: target,
        levels: { level in
          Task { @MainActor in
            appModel.inputLevel = level
          }
        },
        operationStarted: { operationID in
          let accepted = await MainActor.run {
            guard appModel.operationAttemptID == attemptID else {
              return false
            }
            appModel.operationID = operationID
            appModel.operationMode = .dictation
            appModel.operationTarget = target
            appModel.operationPhase = .recording
            return true
          }
          if !accepted {
            await coordinator.cancel(operationID: operationID)
          }
        }
      )
      guard operationAttemptID == attemptID else {
        return
      }
      operationStartupMode = nil
      if pendingStopMode == .dictation {
        pendingStopMode = nil
        await finishDictation()
      }
    } catch {
      await targetTracker.release(target)
      guard operationAttemptID == attemptID else {
        return
      }
      if error as? MicAIError == .cancelled {
        clearOperation(ifAttemptID: attemptID)
        hotkeyMonitor.reset(mode: .dictation)
        return
      }
      errorMessage = error.localizedDescription
      operationPhase = .failed((error as? MicAIError) ?? .audioUnavailable)
      clearOperation(ifAttemptID: attemptID)
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
        let coordinator = self.coordinator
        try await insertionCoordinator.apply(
          .insert(transcript.text),
          to: target,
          while: {
            await coordinator.isCurrent(operationID: operationID)
          }
        )
      } catch let error as MicAIError where error == .clipboardChanged {
        guard await coordinator.complete(operationID: operationID) else {
          throw MicAIError.cancelled
        }
        complete(transcript: transcript, diagnostic: error.localizedDescription)
        return
      }

      guard await coordinator.complete(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      complete(transcript: transcript)
    } catch {
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      if micAIError == .cancelled,
        !(await coordinator.isCurrent(operationID: operationID))
      {
        return
      }
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

  private func startCommand() async {
    guard operationID == nil, operationAttemptID == nil else {
      hotkeyMonitor.reset(mode: .command)
      return
    }
    let attemptID = UUID()
    operationAttemptID = attemptID
    operationStartupMode = .command
    guard settingsStore.settings.commandHotkey != nil,
      !settingsStore.settings.llmModel
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      rejectCommandStart(with: .llmServerFailure)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    guard modelState == .ready else {
      rejectCommandStart(with: .asrNotInitialized)
      clearOperation(ifAttemptID: attemptID)
      return
    }

    microphonePermission.refresh()
    guard microphonePermission.isGranted else {
      rejectCommandStart(with: .microphoneDenied)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    accessibilityPermission.refresh()
    guard accessibilityPermission.isTrusted else {
      rejectCommandStart(with: .accessibilityDenied)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    guard let target = await targetTracker.capture() else {
      rejectCommandStart(with: .targetChanged)
      clearOperation(ifAttemptID: attemptID)
      return
    }

    do {
      errorMessage = nil
      lastTranscript = nil
      let appModel = self
      let coordinator = self.coordinator
      _ = try await commandPipeline.begin(
        target: target,
        levels: { level in
          Task { @MainActor in
            appModel.inputLevel = level
          }
        },
        operationStarted: { operationID in
          let accepted = await MainActor.run {
            guard appModel.operationAttemptID == attemptID else {
              return false
            }
            appModel.operationID = operationID
            appModel.operationMode = .command
            appModel.operationTarget = target
            appModel.operationPhase = .recording
            return true
          }
          if !accepted {
            await coordinator.cancel(operationID: operationID)
          }
        }
      )
      guard operationAttemptID == attemptID else {
        return
      }
      operationStartupMode = nil
      if pendingStopMode == .command {
        pendingStopMode = nil
        await finishCommand()
      }
    } catch {
      await targetTracker.release(target)
      guard operationAttemptID == attemptID else {
        return
      }
      if error as? MicAIError == .cancelled {
        clearOperation(ifAttemptID: attemptID)
        hotkeyMonitor.reset(mode: .command)
        return
      }
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
      clearOperation(ifAttemptID: attemptID)
      hotkeyMonitor.reset(mode: .command)
    }
  }

  private func finishCommand() async {
    guard let operationID, let target = operationTarget else {
      return
    }

    operationPhase = .transcribing
    inputLevel = 0
    do {
      let appModel = self
      let result = try await commandPipeline.finish(
        operationID: operationID,
        model: settingsStore.settings.llmModel,
        awaitingLLM: {
          await MainActor.run {
            appModel.operationPhase = .awaitingLLM
          }
        }
      )
      guard await coordinator.markInserting(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      operationPhase = .inserting
      accessibilityPermission.refresh()
      guard accessibilityPermission.isTrusted else {
        throw MicAIError.accessibilityDenied
      }

      do {
        let coordinator = self.coordinator
        try await insertionCoordinator.apply(
          result.intent,
          to: target,
          while: {
            await coordinator.isCurrent(operationID: operationID)
          }
        )
      } catch let error as MicAIError where error == .clipboardChanged {
        guard await coordinator.complete(operationID: operationID) else {
          throw MicAIError.cancelled
        }
        complete(
          transcript: result.instruction,
          diagnostic: error.localizedDescription
        )
        return
      }

      guard await coordinator.complete(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      providerStatus = .readyToAttempt
      complete(transcript: result.instruction)
    } catch {
      let micAIError = (error as? MicAIError) ?? .llmServerFailure
      if micAIError == .cancelled,
        !(await coordinator.isCurrent(operationID: operationID))
      {
        return
      }
      providerStatus = .failed(micAIError)
      if await coordinator.isCurrent(operationID: operationID) {
        _ = await coordinator.fail(operationID: operationID, error: micAIError)
      }
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
      clearOperation()
    }
  }

  private func cancelCommand() async {
    guard let operationID else {
      return
    }
    await commandPipeline.cancel(operationID: operationID)
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

  private func clearOperation(ifAttemptID expectedAttemptID: UUID? = nil) {
    if let expectedAttemptID, operationAttemptID != expectedAttemptID {
      return
    }
    if let operationTarget {
      let targetTracker = self.targetTracker
      Task {
        await targetTracker.release(operationTarget)
      }
    }
    operationID = nil
    operationAttemptID = nil
    operationStartupMode = nil
    pendingStopMode = nil
    operationMode = nil
    operationTarget = nil
  }

  private func rejectDictationStart(with error: MicAIError) {
    errorMessage = error.localizedDescription
    hotkeyMonitor.reset(mode: .dictation)
  }

  private func rejectCommandStart(with error: MicAIError) {
    errorMessage = error.localizedDescription
    hotkeyMonitor.reset(mode: .command)
  }

  private func cancelActiveOperation() async {
    guard operationID != nil || operationAttemptID != nil else {
      return
    }
    guard operationID != nil else {
      operationAttemptID = nil
      operationPhase = .idle
      inputLevel = 0
      hotkeyMonitor.reset(mode: .dictation)
      hotkeyMonitor.reset(mode: .command)
      return
    }
    switch operationMode {
    case .dictation:
      await cancelDictation()
    case .command:
      await cancelCommand()
    case nil:
      return
    }
    hotkeyMonitor.reset(mode: .dictation)
    hotkeyMonitor.reset(mode: .command)
  }

  private func refreshProviderStatus() {
    let settings = settingsStore.settings
    let configured =
      settings.commandHotkey != nil
      && !settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    providerStatus = configured ? .readyToAttempt : .notConfigured
  }

  private static func makeTransformer(
    for provider: LLMProvider,
    statusHandler: @escaping @Sendable (ProviderStatus) -> Void
  ) -> any LLMTransforming {
    switch provider {
    case .openAIAPIKey:
      OpenAIAPIKeyClient()
    case .chatGPTSubscription:
      ChatGPTResponsesClient(
        credentialLoader: CodexAuthFileLoader(),
        statusHandler: statusHandler
      )
    }
  }
}

private final class ProviderStatusRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable (ProviderStatus) -> Void)?

  func setHandler(
    _ handler: @escaping @Sendable (ProviderStatus) -> Void
  ) {
    lock.lock()
    self.handler = handler
    lock.unlock()
  }

  func send(_ status: ProviderStatus) {
    lock.lock()
    let handler = self.handler
    lock.unlock()
    handler?(status)
  }
}
