import Combine
import Foundation
import MicAICore

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var modelState: ModelPreparationState = .notDownloaded
  @Published private(set) var operationPhase: OperationPhase = .idle
  @Published private(set) var hudMode: MicAIMode?
  @Published private(set) var inputLevel: Float = 0
  @Published private(set) var lastTranscript: String?
  @Published private(set) var errorMessage: String?
  @Published private(set) var providerStatus: ProviderStatus = .notConfigured
  @Published private(set) var dictationProviderStatus: DictationProviderStatus =
    .parakeetNotReady
  @Published private(set) var recoverableInsertion: RecoverableInsertion?
  @Published private(set) var isRecoveringInsertion = false
  @Published private(set) var pendingProofDraft: ProofCarryingDraft?
  @Published private(set) var lastProofDraft: ProofCarryingDraft?
  @Published private(set) var isResolvingProofDraft = false
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
  private var operationTranscriptionRequest: SpeechTranscriptionRequest?
  private var operationTarget: TargetIdentity?
  private var operationStartedAt: Date?
  private var isFinishingOperation = false
  private var settingsApplicationPending = false
  private var recoverableInsertionContext: RecoverableInsertionContext?
  private var pendingProofDraftContext: PendingProofDraftContext?
  private var cancellables: Set<AnyCancellable> = []

  #if DEBUG
    private var lastAppliedSettingsForTesting: AppSettings?
    private var settingsApplyCountForTesting = 0
  #endif

  private struct RecordingCallbacks: Sendable {
    let levels: @Sendable (Float) -> Void
    let maximumDurationReached: @Sendable () -> Void
  }

  private lazy var hotkeyMonitor = GlobalHotkeyMonitor(
    settings: settingsStore.settings,
    actionHandler: { [weak self] mode, action in
      self?.handleHotkey(mode: mode, action: action)
    },
    cancelHandler: { [weak self] in
      self?.cancelCurrentOperation()
    }
  )

  init(
    startRuntime: Bool = true,
    settingsDefaults: UserDefaults = .standard,
    openAIAPIKeyProvider: any OpenAIAPIKeyProviding = UnavailableOpenAIAPIKeyProvider(),
    openAITranscriptionTransport: any OpenAITranscriptionHTTPTransport =
      URLSessionOpenAITranscriptionTransport()
  ) {
    let settingsStore = SettingsStore(defaults: settingsDefaults)
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
    let transcriptionRouter = SpeechTranscriptionRouter(
      parakeet: recognizer,
      openAI: OpenAITranscriptionClient(
        apiKeyProvider: openAIAPIKeyProvider,
        transport: openAITranscriptionTransport
      )
    )
    pipeline = DictationPipeline(
      audioCapture: AVAudioEngineCapture(),
      recognizer: recognizer,
      transcriptionRouter: transcriptionRouter,
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
        transformer: ChatGPTResponsesClient(
          credentialLoader: CodexAuthFileLoader(),
          scopedStatusHandler: { requestID, status in
            _ = providerStatusRelay.send(requestID: requestID, status: status)
          }
        )
      ),
      insertionCoordinator: insertionCoordinator,
      coordinator: coordinator
    )
    let uiFixture = ProcessInfo.processInfo.environment["MICAI_UI_FIXTURE"]
    isOnboardingPresented = uiFixture == nil && !settingsStore.hasSeenOnboarding
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
    Publishers.CombineLatest4($hudMode, $operationPhase, $inputLevel, $errorMessage)
      .sink { [weak self] mode, phase, level, message in
        self?.hudController.update(
          mode: mode,
          phase: phase,
          level: level,
          message: message
        )
      }
      .store(in: &cancellables)
    providerStatusRelay.setHandler { [weak self] requestID, status in
      await self?.applyProviderStatus(status, requestID: requestID)
    }
    refreshDictationProviderStatus()

    if let uiFixture, uiFixture.hasPrefix("proof") {
      installProofFixture(
        targetUnavailable: uiFixture == "proof-target-unavailable"
      )
    } else if let uiFixture, uiFixture.hasPrefix("hud-") {
      installHUDFixture(uiFixture)
    } else if startRuntime {
      Task { @MainActor [weak self] in
        self?.refreshSystemStatus()
        self?.refreshProviderStatus()
        self?.hotkeyMonitor.start()
        await self?.prepareCachedModelIfAvailable()
      }
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
      operationActive:
        operationID != nil || operationAttemptID != nil || isRecoveringInsertion,
      recoveryPending: recoverableInsertion != nil || pendingProofDraft != nil,
      dictationProvider: settingsStore.settings.dictationProvider,
      openAITranscriptionConfigured: false,
      dictationFallbackEnabled:
        settingsStore.settings.openAITranscriptionFallbackEnabled
    )
  }

  var isOperationActive: Bool {
    operationID != nil || operationAttemptID != nil || isResolvingProofDraft
  }

  var canApplySettings: Bool {
    !isOperationActive
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
            appModel.refreshDictationProviderStatus()
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
          appModel.refreshDictationProviderStatus()
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
    guard canApplySettings else {
      settingsApplicationPending = true
      return
    }
    settingsApplicationPending = false
    let settings = settingsStore.settings
    hotkeyMonitor.update(settings: settings)
    refreshProviderStatus()
    refreshDictationProviderStatus()
    #if DEBUG
      lastAppliedSettingsForTesting = settings
      settingsApplyCountForTesting += 1
    #endif
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

  func copyRecoverableResult() {
    Task {
      await copyRecoverableResultToPasteboard()
    }
  }

  func retryRecoverableInsertion() {
    Task {
      await retryOriginalInsertion()
    }
  }

  func dismissRecoverableInsertion() {
    guard recoverableInsertionContext != nil else {
      return
    }
    MicAITelemetry.recoveryDismissed()
    clearRecoverableInsertion()
    errorMessage = nil
    hudMode = nil
    operationPhase = .idle
  }

  func approveProofDraft() {
    Task {
      await approvePendingProofDraft()
    }
  }

  func copyProofDraft() {
    Task {
      await copyPendingProofDraft()
    }
  }

  func discardProofDraft() {
    guard let context = pendingProofDraftContext else {
      return
    }
    clearPendingProofDraft(releasing: context.target)
    errorMessage = nil
    hudMode = nil
    operationPhase = .idle
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
    guard operationID == nil, operationAttemptID == nil, !isRecoveringInsertion else {
      hotkeyMonitor.reset(mode: .dictation)
      return
    }
    guard recoverableInsertionContext == nil, pendingProofDraftContext == nil else {
      rejectDictationStart(with: .recoveryPending)
      return
    }
    let attemptID = UUID()
    operationAttemptID = attemptID
    operationStartupMode = .dictation
    let transcriptionRequest = settingsStore.settings.dictationTranscriptionRequest
    if let routeError = dictationRouteError(for: transcriptionRequest) {
      rejectDictationStart(with: routeError)
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
      let callbacks = recordingCallbacks(
        mode: .dictation,
        attemptID: attemptID
      )
      _ = try await pipeline.begin(
        target: target,
        transcriptionRequest: transcriptionRequest,
        levels: callbacks.levels,
        maximumDurationReached: callbacks.maximumDurationReached,
        operationStarted: { operationID in
          let accepted = await MainActor.run {
            guard appModel.operationAttemptID == attemptID else {
              return false
            }
            appModel.operationID = operationID
            appModel.operationMode = .dictation
            appModel.operationTranscriptionRequest = transcriptionRequest
            appModel.operationTarget = target
            appModel.hudMode = .dictation
            appModel.operationPhase = .recording
            appModel.operationStartedAt = Date()
            MicAITelemetry.operationStarted(mode: .dictation)
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
      let micAIError = (error as? MicAIError) ?? .audioUnavailable
      MicAITelemetry.operationFailed(mode: .dictation, error: micAIError)
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
      clearOperation(ifAttemptID: attemptID)
      hotkeyMonitor.reset(mode: .dictation)
    }
  }

  private func finishDictation() async {
    guard let operationID, let target = operationTarget, !isFinishingOperation else {
      return
    }
    isFinishingOperation = true

    var pendingIntent: InsertionIntent?
    operationPhase = .transcribing
    MicAITelemetry.operationEntered("transcribing", mode: .dictation)
    inputLevel = 0
    do {
      let appModel = self
      let transcript = try await pipeline.finish(
        operationID: operationID,
        providerStatus: { requestID, status in
          await MainActor.run {
            appModel.applyDictationProviderStatus(
              status,
              requestID: requestID
            )
          }
        }
      )
      guard ownsOperation(operationID) else {
        return
      }
      let intent = InsertionIntent.insert(transcript.text)
      pendingIntent = intent
      let markedInserting = await coordinator.markInserting(operationID: operationID)
      guard ownsOperation(operationID) else {
        return
      }
      guard markedInserting else {
        throw MicAIError.cancelled
      }
      operationPhase = .inserting
      MicAITelemetry.operationEntered("inserting", mode: .dictation)
      accessibilityPermission.refresh()
      guard accessibilityPermission.isTrusted else {
        throw MicAIError.accessibilityDenied
      }

      do {
        let coordinator = self.coordinator
        try await insertionCoordinator.apply(
          intent,
          to: target,
          while: {
            await coordinator.isCurrent(operationID: operationID)
          }
        )
        guard ownsOperation(operationID) else {
          return
        }
      } catch let error as MicAIError
        where error == .clipboardChanged
        || error == .clipboardRestoreFailedAfterInsertion
      {
        let completed = await coordinator.complete(operationID: operationID)
        guard ownsOperation(operationID) else {
          return
        }
        guard completed else {
          throw MicAIError.cancelled
        }
        complete(
          operationID: operationID,
          resultText: intent.text,
          mode: .dictation,
          diagnostic: error.localizedDescription
        )
        return
      }

      let completed = await coordinator.complete(operationID: operationID)
      guard ownsOperation(operationID) else {
        return
      }
      guard completed else {
        throw MicAIError.cancelled
      }
      complete(
        operationID: operationID,
        resultText: intent.text,
        mode: .dictation
      )
    } catch {
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      await handleFinishFailure(
        operationID: operationID,
        target: target,
        pendingIntent: pendingIntent,
        error: micAIError,
        mode: .dictation
      )
    }
  }

  private func cancelDictation() async {
    guard let operationID else {
      return
    }
    await pipeline.cancel(operationID: operationID)
    guard ownsOperation(operationID) else {
      return
    }
    MicAITelemetry.operationCancelled(mode: .dictation)
    hudMode = nil
    operationPhase = .idle
    errorMessage = nil
    inputLevel = 0
    clearOperation(ifOperationID: operationID)
    refreshDictationProviderStatus()
  }

  private func startCommand() async {
    guard operationID == nil, operationAttemptID == nil, !isRecoveringInsertion else {
      hotkeyMonitor.reset(mode: .command)
      return
    }
    guard recoverableInsertionContext == nil, pendingProofDraftContext == nil else {
      rejectCommandStart(with: .recoveryPending)
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
      let callbacks = recordingCallbacks(
        mode: .command,
        attemptID: attemptID
      )
      _ = try await commandPipeline.begin(
        target: target,
        levels: callbacks.levels,
        maximumDurationReached: callbacks.maximumDurationReached,
        operationStarted: { operationID in
          let accepted = await MainActor.run {
            guard appModel.operationAttemptID == attemptID else {
              return false
            }
            appModel.operationID = operationID
            appModel.operationMode = .command
            appModel.operationTarget = target
            appModel.hudMode = .command
            appModel.operationPhase = .recording
            appModel.operationStartedAt = Date()
            MicAITelemetry.operationStarted(mode: .command)
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
      MicAITelemetry.operationFailed(mode: .command, error: micAIError)
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
      clearOperation(ifAttemptID: attemptID)
      hotkeyMonitor.reset(mode: .command)
    }
  }

  private func finishCommand() async {
    guard let operationID, let target = operationTarget, !isFinishingOperation else {
      return
    }
    isFinishingOperation = true

    var pendingIntent: InsertionIntent?
    operationPhase = .transcribing
    MicAITelemetry.operationEntered("transcribing", mode: .command)
    inputLevel = 0
    do {
      let appModel = self
      let result = try await commandPipeline.finish(
        operationID: operationID,
        model: settingsStore.settings.llmModel,
        awaitingLLM: {
          await MainActor.run {
            guard appModel.ownsOperation(operationID) else {
              return
            }
            appModel.operationPhase = .awaitingLLM
            MicAITelemetry.operationEntered("awaiting_llm", mode: .command)
          }
        }
      )
      guard ownsOperation(operationID) else {
        return
      }
      pendingIntent = result.intent
      providerStatus = .readyToAttempt
      let markedInserting = await coordinator.markInserting(operationID: operationID)
      guard ownsOperation(operationID) else {
        return
      }
      guard markedInserting else {
        throw MicAIError.cancelled
      }
      operationPhase = .inserting
      MicAITelemetry.operationEntered("preparing_proof", mode: .command)
      let completed = await coordinator.complete(operationID: operationID)
      guard ownsOperation(operationID) else {
        return
      }
      guard completed else {
        throw MicAIError.cancelled
      }
      stageProofDraft(
        operationID: operationID,
        result: result,
        target: target
      )
    } catch {
      let micAIError = (error as? MicAIError) ?? .llmServerFailure
      await handleFinishFailure(
        operationID: operationID,
        target: target,
        pendingIntent: pendingIntent,
        error: micAIError,
        mode: .command
      )
    }
  }

  private func cancelCommand() async {
    guard let operationID else {
      return
    }
    await commandPipeline.cancel(operationID: operationID)
    guard ownsOperation(operationID) else {
      return
    }
    MicAITelemetry.operationCancelled(mode: .command)
    hudMode = nil
    operationPhase = .idle
    errorMessage = nil
    inputLevel = 0
    clearOperation(ifOperationID: operationID)
    refreshProviderStatus()
  }

  private func complete(
    operationID completedOperationID: UUID,
    resultText: String,
    mode: MicAIMode,
    diagnostic: String? = nil
  ) {
    guard ownsOperation(completedOperationID) else {
      return
    }
    let duration = operationStartedAt.map { Date().timeIntervalSince($0) } ?? 0
    MicAITelemetry.operationCompleted(mode: mode, duration: duration)
    lastTranscript = resultText
    errorMessage = diagnostic
    hudMode = nil
    operationPhase = .idle
    clearOperation(ifOperationID: completedOperationID)
  }

  private func stageProofDraft(
    operationID completedOperationID: UUID,
    result: CommandResult,
    target: TargetIdentity
  ) {
    guard ownsOperation(completedOperationID) else {
      return
    }
    let targetLabel =
      target.applicationName
      ?? target.bundleIdentifier
      ?? "the original field"
    let draft = ProofCarryingDraft.transformation(
      instruction: result.instruction.text,
      sourceText: result.sourceText,
      proposedText: result.intent.text,
      targetLabel: targetLabel
    )
    let duration = operationStartedAt.map { Date().timeIntervalSince($0) } ?? 0
    MicAITelemetry.operationCompleted(mode: .command, duration: duration)
    pendingProofDraft = draft
    pendingProofDraftContext = PendingProofDraftContext(
      draft: draft,
      intent: result.intent,
      target: target,
      fixtureFailure: nil
    )
    lastProofDraft = nil
    lastTranscript = nil
    errorMessage = nil
    hudMode = nil
    operationPhase = .idle
    clearOperation(
      ifOperationID: completedOperationID,
      releaseTarget: false
    )
  }

  private func clearOperation(
    ifOperationID expectedOperationID: UUID? = nil,
    ifAttemptID expectedAttemptID: UUID? = nil,
    releaseTarget: Bool = true
  ) {
    if let expectedOperationID, operationID != expectedOperationID {
      return
    }
    if let expectedAttemptID, operationAttemptID != expectedAttemptID {
      return
    }
    if releaseTarget, let operationTarget {
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
    operationTranscriptionRequest = nil
    operationTarget = nil
    operationStartedAt = nil
    isFinishingOperation = false
    applyPendingSettingsIfIdle()
  }

  private func applyPendingSettingsIfIdle() {
    guard settingsApplicationPending, canApplySettings else {
      return
    }
    applySettings()
  }

  private func ownsOperation(_ expectedOperationID: UUID) -> Bool {
    operationID == expectedOperationID
  }

  private func handleFinishFailure(
    operationID completedOperationID: UUID,
    target: TargetIdentity,
    pendingIntent: InsertionIntent?,
    error: MicAIError,
    mode: MicAIMode
  ) async {
    guard ownsOperation(completedOperationID) else {
      return
    }
    if error == .cancelled,
      await resolveNonCurrentCancellation(
        operationID: completedOperationID,
        mode: mode
      )
    {
      return
    }
    guard ownsOperation(completedOperationID) else {
      return
    }
    if mode == .command {
      providerStatus = providerStatus(after: error)
    }
    let isCurrent = await coordinator.isCurrent(operationID: completedOperationID)
    guard ownsOperation(completedOperationID) else {
      return
    }
    if isCurrent {
      _ = await coordinator.fail(operationID: completedOperationID, error: error)
      guard ownsOperation(completedOperationID) else {
        return
      }
    }
    MicAITelemetry.operationFailed(mode: mode, error: error)
    errorMessage = error.localizedDescription
    operationPhase = .failed(error)
    if let pendingIntent, error != .cancelled {
      retainRecoverableInsertion(
        intent: pendingIntent,
        target: target,
        failure: error,
        mode: mode
      )
      clearOperation(
        ifOperationID: completedOperationID,
        releaseTarget: false
      )
    } else {
      clearOperation(ifOperationID: completedOperationID)
    }
  }

  private func resolveNonCurrentCancellation(
    operationID completedOperationID: UUID,
    mode: MicAIMode
  ) async -> Bool {
    guard !(await coordinator.isCurrent(operationID: completedOperationID)) else {
      return false
    }
    guard operationID == completedOperationID else {
      return true
    }
    MicAITelemetry.operationCancelled(mode: mode)
    hudMode = nil
    operationPhase = .idle
    errorMessage = nil
    inputLevel = 0
    clearOperation(ifOperationID: completedOperationID)
    return true
  }

  #if DEBUG
    func beginOperationForTesting(
      mode: MicAIMode,
      attemptID: UUID = UUID()
    ) async throws -> UUID {
      guard operationID == nil, operationAttemptID == nil else {
        throw MicAIError.invalidTransition
      }
      let target = TargetIdentity(processIdentifier: 42)
      operationAttemptID = attemptID
      operationStartupMode = mode
      let startedOperationID = try await coordinator.begin(
        mode: mode,
        target: target
      )
      operationID = startedOperationID
      operationMode = mode
      operationTarget = target
      operationStartupMode = nil
      hudMode = mode
      operationPhase = .recording
      return startedOperationID
    }

    func beginCommandOperationForTesting() async throws -> UUID {
      try await beginOperationForTesting(mode: .command)
    }

    func finishCommandWithTransportCancellationForTesting(
      operationID completedOperationID: UUID
    ) async {
      guard let target = operationTarget else {
        return
      }
      isFinishingOperation = true
      operationPhase = .awaitingLLM
      _ = await coordinator.fail(
        operationID: completedOperationID,
        error: .cancelled
      )
      await handleFinishFailure(
        operationID: completedOperationID,
        target: target,
        pendingIntent: nil,
        error: .cancelled,
        mode: .command
      )
    }

    func cancelOperationForTesting(operationID: UUID) async {
      await coordinator.cancel(operationID: operationID)
      if self.operationID == operationID {
        clearOperation(ifOperationID: operationID)
        hudMode = nil
        operationPhase = .idle
      }
    }

    func cancelCommandOperationForTesting(operationID: UUID) async {
      guard self.operationID == operationID else {
        return
      }
      await cancelCommand()
    }

    func markCommandPreparingProofForTesting(
      operationID completedOperationID: UUID
    ) async throws {
      guard ownsOperation(completedOperationID) else {
        throw MicAIError.invalidTransition
      }
      await coordinator.stopRecording(operationID: completedOperationID)
      guard await coordinator.markAwaitingLLM(operationID: completedOperationID) else {
        throw MicAIError.invalidTransition
      }
      let markedInserting = await coordinator.markInserting(
        operationID: completedOperationID
      )
      guard ownsOperation(completedOperationID), markedInserting else {
        throw MicAIError.cancelled
      }
      operationPhase = .inserting
    }

    func rejectStartForTesting(mode: MicAIMode, error: MicAIError) {
      switch mode {
      case .dictation:
        rejectDictationStart(with: error)
      case .command:
        rejectCommandStart(with: error)
      }
    }

    func applyLateFinishErrorForTesting(
      operationID completedOperationID: UUID,
      mode: MicAIMode,
      error: MicAIError
    ) async {
      await handleFinishFailure(
        operationID: completedOperationID,
        target: TargetIdentity(processIdentifier: 42),
        pendingIntent: nil,
        error: error,
        mode: mode
      )
    }

    func recordingCallbacksForTesting(
      mode: MicAIMode,
      attemptID: UUID
    ) -> RecordingCallbacksForTesting {
      let levelCompletion = RecordingCallbackCompletion()
      let maximumDurationCompletion = RecordingCallbackCompletion()
      let callbacks = recordingCallbacks(
        mode: mode,
        attemptID: attemptID,
        levelHandled: {
          levelCompletion.signal()
        },
        maximumDurationHandled: {
          maximumDurationCompletion.signal()
        }
      )
      return RecordingCallbacksForTesting(
        levels: { level in
          callbacks.levels(level)
          await levelCompletion.wait()
        },
        maximumDurationReached: {
          callbacks.maximumDurationReached()
          await maximumDurationCompletion.wait()
        }
      )
    }

    func sendProviderStatusForTesting(
      requestID: UUID,
      status: ProviderStatus
    ) async {
      await providerStatusRelay.send(requestID: requestID, status: status).value
    }

    func sendDictationProviderStatusForTesting(
      requestID: UUID,
      status: DictationProviderStatus
    ) {
      applyDictationProviderStatus(status, requestID: requestID)
    }

    var operationIDForTesting: UUID? {
      operationID
    }

    var isFinishingOperationForTesting: Bool {
      isFinishingOperation
    }

    var deferredSettingsApplicationForTesting: Bool {
      settingsApplicationPending
    }

    var appliedSettingsForTesting: AppSettings? {
      lastAppliedSettingsForTesting
    }

    var appliedSettingsCountForTesting: Int {
      settingsApplyCountForTesting
    }

    func setModelStateForTesting(_ state: ModelPreparationState) {
      modelState = state
      refreshDictationProviderStatus()
    }

    func installProofFixtureForTesting(
      failure: MicAIError = .targetChanged
    ) {
      installProofFixture(
        targetUnavailable: false,
        fixtureFailure: failure
      )
    }

    func approveProofFixtureForTesting() async {
      await approvePendingProofDraft()
    }
  #endif

  private func retainRecoverableInsertion(
    intent: InsertionIntent,
    target: TargetIdentity,
    failure: MicAIError,
    mode: MicAIMode
  ) {
    let result = RecoverableInsertion(
      id: UUID(),
      text: intent.text,
      failure: failure
    )
    recoverableInsertion = result
    recoverableInsertionContext = RecoverableInsertionContext(
      result: result,
      intent: intent,
      target: target,
      mode: mode
    )
    MicAITelemetry.recoveryCreated(mode: mode, error: failure)
  }

  private func copyRecoverableResultToPasteboard() async {
    guard !isRecoveringInsertion, let context = recoverableInsertionContext else {
      return
    }
    isRecoveringInsertion = true
    defer {
      isRecoveringInsertion = false
    }
    do {
      try await insertionCoordinator.copyResult(context.intent.text)
      MicAITelemetry.recoveryCopied()
      lastTranscript = context.intent.text
      errorMessage = nil
      hudMode = nil
      operationPhase = .idle
      clearRecoverableInsertion()
    } catch {
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      updateRecoverableInsertion(context: context, failure: micAIError)
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
    }
  }

  private func retryOriginalInsertion() async {
    guard !isRecoveringInsertion, let context = recoverableInsertionContext else {
      return
    }
    isRecoveringInsertion = true
    defer {
      isRecoveringInsertion = false
    }

    do {
      accessibilityPermission.refresh()
      guard accessibilityPermission.isTrusted else {
        throw MicAIError.accessibilityDenied
      }
      guard await targetTracker.reactivate(context.target) else {
        throw MicAIError.targetChanged
      }
      var diagnostic: String?
      do {
        try await insertionCoordinator.apply(
          context.intent,
          to: context.target
        )
      } catch let error as MicAIError
        where error == .clipboardChanged
        || error == .clipboardRestoreFailedAfterInsertion
      {
        diagnostic = error.localizedDescription
      }

      MicAITelemetry.recoveryRetried(succeeded: true)
      lastTranscript = context.intent.text
      errorMessage = diagnostic
      hudMode = nil
      operationPhase = .idle
      clearRecoverableInsertion()
    } catch {
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      MicAITelemetry.recoveryRetried(succeeded: false)
      updateRecoverableInsertion(context: context, failure: micAIError)
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
    }
  }

  private func updateRecoverableInsertion(
    context: RecoverableInsertionContext,
    failure: MicAIError
  ) {
    let result = RecoverableInsertion(
      id: context.result.id,
      text: context.intent.text,
      failure: failure
    )
    recoverableInsertion = result
    recoverableInsertionContext = RecoverableInsertionContext(
      result: result,
      intent: context.intent,
      target: context.target,
      mode: context.mode
    )
  }

  private func clearRecoverableInsertion() {
    guard let context = recoverableInsertionContext else {
      recoverableInsertion = nil
      return
    }
    recoverableInsertion = nil
    recoverableInsertionContext = nil
    let targetTracker = self.targetTracker
    Task {
      await targetTracker.release(context.target)
    }
  }

  private func approvePendingProofDraft() async {
    guard !isResolvingProofDraft, let context = pendingProofDraftContext else {
      return
    }
    isResolvingProofDraft = true
    defer {
      isResolvingProofDraft = false
    }

    do {
      if let fixtureFailure = context.fixtureFailure {
        throw fixtureFailure
      }
      accessibilityPermission.refresh()
      guard accessibilityPermission.isTrusted else {
        throw MicAIError.accessibilityDenied
      }
      guard await targetTracker.reactivate(context.target) else {
        throw MicAIError.targetChanged
      }
      if case .replaceSelection = context.intent {
        let currentSelection = try await insertionCoordinator.readSelection(
          from: context.target
        )
        guard context.matchesCurrentSelection(currentSelection) else {
          throw MicAIError.targetChanged
        }
      }

      var diagnostic: String?
      do {
        try await insertionCoordinator.apply(
          context.intent,
          to: context.target
        )
      } catch let error as MicAIError where error == .clipboardChanged {
        diagnostic = error.localizedDescription
      }

      let approved = context.draft.updating(
        state: .approved,
        notice: "Inserted only after approval into \(context.draft.targetLabel)."
      )
      lastProofDraft = approved
      lastTranscript = context.intent.text
      errorMessage = diagnostic
      hudMode = nil
      operationPhase = .idle
      clearPendingProofDraft(releasing: context.target)
    } catch {
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      if micAIError == .clipboardRestoreFailedAfterInsertion {
        let uncertain = context.draft.updating(
          state: .insertionUncertain,
          notice:
            "Paste was sent, but MicAI could not prove whether the target accepted it. Check the original field before acting again. Approval cannot be retried automatically."
        )
        lastProofDraft = uncertain
        lastTranscript = context.intent.text
        errorMessage = micAIError.localizedDescription
        hudMode = nil
        operationPhase = .idle
        clearPendingProofDraft(releasing: context.target)
        return
      }
      let isTargetFailure = micAIError == .targetChanged
      let failed = context.draft.updating(
        state: isTargetFailure ? .targetUnavailable : .approvalFailed,
        notice: isTargetFailure
          ? "The target lock stopped insertion. The draft remains safe in this session."
          : "Approval did not complete. The draft remains safe in this session. \(micAIError.localizedDescription)"
      )
      pendingProofDraft = failed
      pendingProofDraftContext = PendingProofDraftContext(
        draft: failed,
        intent: context.intent,
        target: context.target,
        fixtureFailure: context.fixtureFailure
      )
      errorMessage = nil
      operationPhase = .failed(micAIError)
    }
  }

  private func copyPendingProofDraft() async {
    guard !isResolvingProofDraft, let context = pendingProofDraftContext else {
      return
    }
    isResolvingProofDraft = true
    defer {
      isResolvingProofDraft = false
    }

    do {
      try await insertionCoordinator.copyResult(context.intent.text)
      let copied = context.draft.updating(
        state: .copied,
        notice: "Copied intentionally. No target app was changed."
      )
      lastProofDraft = copied
      lastTranscript = context.intent.text
      errorMessage = nil
      hudMode = nil
      operationPhase = .idle
      clearPendingProofDraft(releasing: context.target)
    } catch {
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      let failed = context.draft.updating(
        state: .approvalFailed,
        notice:
          "Copy failed. The draft remains safe in this session. \(micAIError.localizedDescription)"
      )
      pendingProofDraft = failed
      pendingProofDraftContext = PendingProofDraftContext(
        draft: failed,
        intent: context.intent,
        target: context.target,
        fixtureFailure: context.fixtureFailure
      )
      operationPhase = .failed(micAIError)
    }
  }

  private func clearPendingProofDraft(releasing target: TargetIdentity) {
    pendingProofDraft = nil
    pendingProofDraftContext = nil
    let targetTracker = self.targetTracker
    Task {
      await targetTracker.release(target)
    }
  }

  private func installProofFixture(
    targetUnavailable: Bool,
    fixtureFailure: MicAIError = .targetChanged
  ) {
    let target = TargetIdentity(
      processIdentifier: -1,
      bundleIdentifier: "com.example.mail",
      applicationName: "Mail — reply field",
      focusToken: UUID()
    )
    let original = ProofCarryingDraft.transformation(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
      instruction: "Make this concise and keep the deadline",
      sourceText:
        "Hi team, I wanted to send a quick reminder that the launch checklist is due by Friday afternoon.",
      proposedText: "Reminder: the launch checklist is due Friday afternoon.",
      targetLabel: "Mail — reply field"
    )
    let draft =
      targetUnavailable
      ? original.updating(
        state: .targetUnavailable,
        notice: "The target lock stopped insertion. The draft remains safe in this session."
      )
      : original
    pendingProofDraft = draft
    pendingProofDraftContext = PendingProofDraftContext(
      draft: draft,
      intent: .replaceSelection(draft.proposedText),
      target: target,
      fixtureFailure: fixtureFailure
    )
    errorMessage = nil
    hudMode = nil
    operationPhase = .idle
  }

  private func installHUDFixture(_ fixture: String) {
    switch fixture {
    case "hud-dictation-recording":
      hudMode = .dictation
      inputLevel = 0.18
      errorMessage = nil
      operationPhase = .recording
    case "hud-command-recording":
      hudMode = .command
      inputLevel = 0.14
      errorMessage = nil
      operationPhase = .recording
    case "hud-command-awaiting":
      hudMode = .command
      inputLevel = 0
      errorMessage = nil
      operationPhase = .awaitingLLM
    case "hud-dictation-failed":
      hudMode = .dictation
      inputLevel = 0
      errorMessage = "The target changed. Open MicAI for recovery options."
      operationPhase = .failed(.targetChanged)
    default:
      hudMode = nil
      inputLevel = 0
      errorMessage = nil
      operationPhase = .idle
    }
  }

  private func recordingCallbacks(
    mode: MicAIMode,
    attemptID: UUID,
    levelHandled: @escaping @Sendable () -> Void = {},
    maximumDurationHandled: @escaping @Sendable () -> Void = {}
  ) -> RecordingCallbacks {
    let appModel = self
    return RecordingCallbacks(
      levels: { level in
        Task { @MainActor in
          appModel.handleInputLevel(
            level,
            mode: mode,
            attemptID: attemptID
          )
          levelHandled()
        }
      },
      maximumDurationReached: {
        Task { @MainActor in
          await appModel.handleMaximumRecordingDuration(
            mode: mode,
            attemptID: attemptID
          )
          maximumDurationHandled()
        }
      }
    )
  }

  private func handleInputLevel(
    _ level: Float,
    mode: MicAIMode,
    attemptID: UUID
  ) {
    guard operationAttemptID == attemptID,
      operationMode == mode,
      operationPhase == .recording
    else {
      return
    }
    inputLevel = level
  }

  private func handleMaximumRecordingDuration(
    mode: MicAIMode,
    attemptID: UUID
  ) async {
    guard operationAttemptID == attemptID,
      operationMode == mode,
      operationPhase == .recording
    else {
      return
    }
    MicAITelemetry.recordingLimitReached(mode: mode)
    hotkeyMonitor.reset(mode: mode)
    switch mode {
    case .dictation:
      await finishDictation()
    case .command:
      await finishCommand()
    }
  }

  private func rejectDictationStart(with error: MicAIError) {
    MicAITelemetry.operationFailed(mode: .dictation, error: error)
    hudMode = .dictation
    errorMessage = error.localizedDescription
    operationPhase = .failed(error)
    hotkeyMonitor.reset(mode: .dictation)
  }

  private func rejectCommandStart(with error: MicAIError) {
    MicAITelemetry.operationFailed(mode: .command, error: error)
    hudMode = .command
    errorMessage = error.localizedDescription
    operationPhase = .failed(error)
    hotkeyMonitor.reset(mode: .command)
  }

  private func cancelActiveOperation() async {
    guard operationID != nil || operationAttemptID != nil else {
      return
    }
    guard operationID != nil else {
      if let operationStartupMode {
        MicAITelemetry.operationCancelled(mode: operationStartupMode)
      }
      clearOperation()
      hudMode = nil
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

  var dictationSelectedRouteLabel: String {
    let settings = settingsStore.settings
    switch settings.dictationProvider {
    case .parakeet:
      return "Parakeet — On-device"
    case .openAI:
      return "OpenAI — \(settings.openAITranscriptionModel)"
    }
  }

  var dictationEffectiveRouteLabel: String {
    let settings = settingsStore.settings
    switch settings.dictationProvider {
    case .parakeet:
      return modelState == .ready ? "Parakeet on-device" : "Parakeet not prepared"
    case .openAI:
      if settings.openAITranscriptionFallbackEnabled {
        return modelState == .ready
          ? "Parakeet fallback — OpenAI not configured"
          : "Blocked — Parakeet fallback not prepared"
      }
      return "Blocked — OpenAI not configured"
    }
  }

  var dictationShortcutDetail: String {
    let action: String
    switch settingsStore.settings.dictationActivationMode {
    case .hold:
      action = "Hold to dictate"
    case .toggle:
      action = "Press once to start and again to stop"
    }
    return "\(action) • Effective: \(dictationEffectiveRouteLabel)"
  }

  var dictationPrivacyDetail: String {
    let settings = settingsStore.settings
    switch settings.dictationProvider {
    case .parakeet where modelState == .ready:
      return
        "Audio is transcribed on this Mac. MicAI does not persist audio or transcript history."
    case .parakeet:
      return
        "Parakeet is selected but not prepared, so dictation is blocked and no audio is sent."
    case .openAI
    where settings.openAITranscriptionFallbackEnabled
      && modelState == .ready:
      return
        "OpenAI is selected but not configured, so no audio is sent. Prepared Parakeet is the effective on-device route."
    case .openAI where settings.openAITranscriptionFallbackEnabled:
      return
        "OpenAI is selected but not configured, and its Parakeet fallback is not prepared. Dictation is blocked and no audio is sent."
    case .openAI:
      return
        "OpenAI is selected but not configured. Dictation is blocked and no audio is sent."
    }
  }

  var isDictationProviderReady: Bool {
    dictationRouteError(for: settingsStore.settings.dictationTranscriptionRequest) == nil
  }

  private func dictationRouteError(
    for request: SpeechTranscriptionRequest
  ) -> MicAIError? {
    switch request.provider {
    case .parakeet:
      return modelState == .ready ? nil : .asrNotInitialized
    case .openAI:
      if request.fallbackToParakeet {
        return modelState == .ready ? nil : .asrNotInitialized
      }
      return .transcriptionNotConfigured
    }
  }

  private func refreshDictationProviderStatus() {
    let settings = settingsStore.settings
    switch settings.dictationProvider {
    case .parakeet:
      dictationProviderStatus =
        modelState == .ready
        ? .parakeetReady : .parakeetNotReady
    case .openAI:
      dictationProviderStatus = .openAINotConfigured(
        fallbackEnabled: settings.openAITranscriptionFallbackEnabled,
        fallbackReady: modelState == .ready
      )
    }
  }

  private func applyDictationProviderStatus(
    _ status: DictationProviderStatus,
    requestID: UUID
  ) {
    guard ownsOperation(requestID), operationMode == .dictation else {
      return
    }
    dictationProviderStatus = status
  }

  private func applyProviderStatus(
    _ status: ProviderStatus,
    requestID: UUID
  ) {
    guard ownsOperation(requestID), operationMode == .command else {
      return
    }
    providerStatus = status
  }

  private func providerStatus(after error: MicAIError) -> ProviderStatus {
    switch error {
    case .credentialMissing, .credentialMalformed, .llmUnauthorized,
      .llmForbidden, .llmRateLimited, .llmServerFailure, .llmIncomplete:
      .failed(error)
    default:
      .readyToAttempt
    }
  }
}

private final class ProviderStatusRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable (UUID, ProviderStatus) async -> Void)?
  private var deliveryTail: Task<Void, Never>?

  func setHandler(
    _ handler: @escaping @Sendable (UUID, ProviderStatus) async -> Void
  ) {
    lock.lock()
    self.handler = handler
    lock.unlock()
  }

  @discardableResult
  func send(
    requestID: UUID,
    status: ProviderStatus
  ) -> Task<Void, Never> {
    lock.lock()
    let handler = self.handler
    let previousDelivery = deliveryTail
    let delivery = Task {
      if let previousDelivery {
        await previousDelivery.value
      }
      await handler?(requestID, status)
    }
    deliveryTail = delivery
    lock.unlock()
    return delivery
  }
}

#if DEBUG
  struct RecordingCallbacksForTesting: Sendable {
    let levels: @Sendable (Float) async -> Void
    let maximumDurationReached: @Sendable () async -> Void
  }

  private actor RecordingCallbackCompletion {
    private var pendingSignals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    nonisolated func signal() {
      Task {
        await recordSignal()
      }
    }

    func wait() async {
      if pendingSignals > 0 {
        pendingSignals -= 1
        return
      }
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }

    private func recordSignal() {
      if waiters.isEmpty {
        pendingSignals += 1
      } else {
        waiters.removeFirst().resume()
      }
    }
  }
#endif
