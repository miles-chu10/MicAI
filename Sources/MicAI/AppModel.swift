import AppKit
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
  @Published private(set) var historyEntries: [HistoryEntry] = []
  @Published private(set) var vocabularyEntries: [VocabularyEntry] = []
  @Published private(set) var snippetEntries: [Snippet] = []
  /// The text MicAI last put somewhere: inserted, or shown as an answer. What
  /// "Paste Last Result" pastes again.
  @Published private(set) var lastResult: String?
  /// Finished text the current operation is about to insert. If insertion
  /// fails, it becomes `lastResult` so the menu's Paste and Copy can recover
  /// it without asking the model again.
  private var insertionRecovery = InsertionRecovery()
  /// The mode of the operation in flight, for the HUD and the menu bar icon.
  @Published private(set) var operationMode: MicAIMode?
  /// True after a quick tap in "Hold or tap" mode: recording continues until
  /// the next press.
  @Published private(set) var isHandsFree = false
  /// A rough transcript of what has been said so far, while recording with
  /// live preview on. Never what gets inserted.
  @Published private(set) var livePartial: String?
  /// Tone applied to the most recent dictation, shown in the HUD and history.
  @Published private(set) var lastTone: StyleTone?
  /// Release-to-insertion timings for this session, in memory only.
  @Published private(set) var metrics = LocalMetrics()
  /// Set when an Ask AI result was a question rather than content. The answer
  /// window observes this; nil means no answer is waiting.
  @Published var pendingAnswer: AskAnswer?
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
  private let insertionCoordinator: AdaptiveTextInsertionCoordinator
  private let hudController: RecordingHUDController
  private let providerStatusRelay: ProviderStatusRelay
  private let codexCLIAvailable: Bool
  private let vocabularyStore: VocabularyStore
  private let snippetStore: SnippetStore
  private let historyStore: TranscriptHistoryStore
  private let composer: DictationComposer
  private let translationEngine: TranslationEngine
  private let askEngine: AskEngine
  private let customModeEngine: CustomModeEngine
  /// Set when a custom mode's shortcut is pressed, and read when its
  /// operation starts.
  private var pendingCustomModeID: UUID?
  /// The custom mode the running operation belongs to, captured when it
  /// starts, so editing Settings mid-dictation cannot change what it does.
  private var operationCustomMode: CustomMode?
  private var operationID: UUID?
  private var operationAttemptID: UUID?
  private var operationStartupMode: MicAIMode?
  private var pendingStopMode: MicAIMode?
  private var operationTarget: TargetIdentity?
  /// A speech model chosen while an operation was running. Switching then
  /// would unload the recognizer the recording is about to need, so the
  /// switch waits until the operation ends.
  private var deferredSpeechModel: SpeechModelChoice?
  private var cancellables: Set<AnyCancellable> = []
  private var timingRecorder = PhaseTimingRecorder()

  private lazy var hotkeyMonitor = GlobalHotkeyMonitor(
    settings: settingsStore.settings,
    actionHandler: { [weak self] binding, action in
      self?.handleHotkey(binding: binding, action: action)
    },
    cancelHandler: { [weak self] in
      self?.cancelCurrentOperation()
    }
  )

  init() {
    let settingsStore = SettingsStore()
    let coordinator = OperationCoordinator()
    let recognizer = FluidAudioRecognizer(model: settingsStore.settings.speechModel)
    let targetTracker = TargetApplicationTracker()
    let providerStatusRelay = ProviderStatusRelay()
    let codexExecutableURL = CodexCLIClient.locateExecutable()

    self.settingsStore = settingsStore
    microphonePermission = MicrophonePermissionService()
    accessibilityPermission = AccessibilityPermissionService()
    launchAtLogin = LaunchAtLoginService()
    hudController = RecordingHUDController()
    self.providerStatusRelay = providerStatusRelay
    codexCLIAvailable = codexExecutableURL != nil
    self.coordinator = coordinator
    self.recognizer = recognizer
    self.targetTracker = targetTracker
    pipeline = DictationPipeline(
      audioCapture: AVAudioEngineCapture(),
      recognizer: recognizer,
      cleaner: TranscriptCleaner(),
      coordinator: coordinator
    )
    let clipboardInsertionCoordinator = TextInsertionCoordinator(
      pasteboard: SystemPasteboardAdapter(),
      keyboard: CGEventKeyboardSynthesizer(),
      targetValidator: targetTracker
    )
    insertionCoordinator = AdaptiveTextInsertionCoordinator(
      directInserter: targetTracker,
      clipboardFallback: clipboardInsertionCoordinator
    )
    // One client for every AI path, so a provider status seen by one path is
    // the status every path reports.
    let llmClient = CodexCLIClient(
      executableURL: codexExecutableURL,
      statusHandler: providerStatusRelay.send,
      usageHandler: providerStatusRelay.sendUsage
    )
    commandPipeline = CommandPipeline(
      dictationPipeline: pipeline,
      commandEngine: CommandEngine(transformer: llmClient),
      insertionCoordinator: clipboardInsertionCoordinator,
      coordinator: coordinator
    )
    // Falls back to a temp-directory store if Application Support is
    // unavailable, so a sandbox or disk problem cannot stop dictation.
    let vocabularyStore =
      (try? VocabularyStore.applicationSupport())
      ?? VocabularyStore(
        file: FileManager.default.temporaryDirectory
          .appendingPathComponent("MicAI-vocabulary.json")
      )
    let historyStore =
      (try? TranscriptHistoryStore.applicationSupport(
        limit: settingsStore.settings.historyLimit
      ))
      ?? TranscriptHistoryStore(
        file: FileManager.default.temporaryDirectory
          .appendingPathComponent("MicAI-history.json"),
        limit: settingsStore.settings.historyLimit
      )
    let snippetStore =
      (try? SnippetStore.applicationSupport())
      ?? SnippetStore(
        file: FileManager.default.temporaryDirectory
          .appendingPathComponent("MicAI-snippets.json")
      )
    self.vocabularyStore = vocabularyStore
    self.historyStore = historyStore
    self.snippetStore = snippetStore
    composer = DictationComposer(
      refiner: RefinementEngine(transformer: llmClient),
      vocabulary: vocabularyStore,
      history: historyStore,
      snippets: snippetStore,
      onDeviceRefiner: OnDeviceLanguageModel.makeTransformer().map {
        RefinementEngine(transformer: $0)
      }
    )
    // Both take their per-call settings as arguments: they run off the main
    // actor inside CommandPipeline, so the values are read on the main actor at
    // the call site and passed down.
    translationEngine = TranslationEngine(transformer: llmClient)
    askEngine = AskEngine(transformer: llmClient)
    customModeEngine = CustomModeEngine(transformer: llmClient)
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
    $operationPhase
      .sink { [weak self] phase in
        self?.observeForMetrics(phase)
      }
      .store(in: &cancellables)
    bindHUD()
    providerStatusRelay.setHandler { [weak self] status in
      Task { @MainActor [weak self] in
        self?.providerStatus = status
      }
    }
    providerStatusRelay.setUsageHandler { [weak self] report in
      Task { @MainActor [weak self] in
        self?.metrics.record(report)
      }
    }

    Task { @MainActor [weak self] in
      self?.refreshSystemStatus()
      self?.refreshProviderStatus()
      self?.hotkeyMonitor.start()
      await self?.loadStoredCollections()
      await self?.prepareCachedModelIfAvailable()
    }
  }

  var readiness: AppReadiness {
    AppReadiness(
      microphoneGranted: microphonePermission.isGranted,
      accessibilityGranted: accessibilityPermission.isTrusted,
      speechModelReady: modelState == .ready,
      commandHotkeyConfigured: settingsStore.settings.commandHotkey != nil,
      commandProviderAvailable: codexCLIAvailable,
      operationActive: operationID != nil || operationAttemptID != nil
    )
  }

  /// Feeds the phase stream to the timing recorder and the local OSLog
  /// telemetry. Only modes, phases, error codes and durations are logged —
  /// never transcripts, selections or answers.
  private func observeForMetrics(_ phase: OperationPhase) {
    let mode = operationMode
    switch phase {
    case .recording:
      if let mode {
        MicAITelemetry.operationStarted(mode: mode)
      }
    case .failed(let error):
      if let mode, error != .cancelled {
        MicAITelemetry.operationFailed(mode: mode, error: error)
      }
    case .idle, .transcribing, .awaitingLLM, .inserting:
      break
    }
    if let timing = timingRecorder.observe(phase, mode: mode, at: .now) {
      metrics.record(timing)
      let seconds = timing.releaseToInsertion.components
      MicAITelemetry.operationCompleted(
        mode: timing.mode,
        duration: Double(seconds.seconds) + Double(seconds.attoseconds) / 1e18
      )
    }
  }

  var isCodexCLIInstalled: Bool {
    codexCLIAvailable
  }

  var isOperationActive: Bool {
    operationID != nil || operationAttemptID != nil
  }

  /// Settings are applied between operations so hotkeys and the model cannot
  /// change under a recording that is already in flight.
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
    let settings = settingsStore.settings
    // Privacy mode stops a network mode that is already recording or waiting
    // on the model, not only the next one: otherwise releasing the key after
    // the toggle would still send the selection and transcript out.
    if settings.privacyMode, let mode = operationMode, mode != .dictation {
      Task {
        await abandonSelectionMode(mode, reason: .llmForbidden)
      }
    }
    hotkeyMonitor.update(settings: settings)
    switchSpeechModelIfNeeded(to: settings.speechModel)
    refreshProviderStatus()
    applyHistorySettings(settings)
  }

  /// The store is built once at launch, so a new limit is pushed to it here.
  /// Turning history off deletes what was kept: with nothing new recorded,
  /// the old entries would otherwise stay on disk and in usage statistics.
  private func applyHistorySettings(_ settings: AppSettings) {
    let historyStore = self.historyStore
    Task { @MainActor in
      await historyStore.setLimit(settings.historyLimit)
      if !settings.historyEnabled {
        await historyStore.clear()
      }
      await refreshStoredCollections()
    }
  }

  /// Loads the newly chosen recognizer. Instant when it is already cached;
  /// otherwise the status returns to "not prepared" so Settings offers the
  /// download instead of dictation failing on a model that is not there.
  private func switchSpeechModelIfNeeded(to choice: SpeechModelChoice) {
    guard !isOperationActive else {
      deferredSpeechModel = choice
      return
    }
    deferredSpeechModel = nil
    let recognizer = self.recognizer
    Task { @MainActor in
      guard await recognizer.model != choice else {
        return
      }
      await recognizer.select(choice)
      modelState = .notDownloaded
      await prepareCachedModelIfAvailable()
    }
  }

  func setPrivacyMode(_ enabled: Bool) {
    var settings = settingsStore.settings
    settings.privacyMode = enabled
    if settingsStore.save(settings) {
      applySettings()
      return
    }
    // Privacy mode lets AI shortcuts be saved without a model or language, so
    // turning it off can fail validation. The toggle must still work: save
    // with those requirements waived, leave the modes that lack a value off,
    // and say what is missing.
    let missing = settingsStore.validationMessage
    guard !enabled, settingsStore.save(settings, waivingModelRequirements: true) else {
      return
    }
    applySettings()
    errorMessage = missing
  }

  /// AI text tasks always go to ChatGPT through the signed-in Codex CLI.
  var providerName: String {
    "ChatGPT"
  }

  // MARK: - Last result

  func copyLastResult() {
    guard let lastResult else {
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lastResult, forType: .string)
  }

  /// Pastes the last result into whatever has focus now. For the dictation that
  /// went into the wrong window: switch to the right one and paste it again.
  func pasteLastResult() {
    guard let text = lastResult, !isOperationActive else {
      return
    }
    accessibilityPermission.refresh()
    guard accessibilityPermission.isTrusted else {
      errorMessage = MicAIError.accessibilityDenied.localizedDescription
      return
    }
    let targetTracker = self.targetTracker
    let insertionCoordinator = self.insertionCoordinator
    Task { @MainActor in
      guard let target = await targetTracker.capture() else {
        return
      }
      do {
        try await insertionCoordinator.apply(.insert(text), to: target, while: { true })
      } catch {
        errorMessage = (error as? MicAIError)?.localizedDescription
      }
      await targetTracker.release(target)
    }
  }

  // MARK: - Usage

  func usage(since start: Date? = nil) -> UsageStats {
    UsageStats(entries: historyEntries, since: start)
  }

  // MARK: - HUD

  private func bindHUD() {
    let hud = hudController.model
    $operationMode
      .compactMap { $0 }
      .sink { hud.mode = $0 }
      .store(in: &cancellables)
    $isHandsFree
      .sink { hud.isHandsFree = $0 }
      .store(in: &cancellables)
    $errorMessage
      .sink { hud.message = $0 }
      .store(in: &cancellables)
    $inputLevel
      .sink { hud.push(level: $0) }
      .store(in: &cancellables)
    $livePartial
      .sink { hud.partialText = $0 }
      .store(in: &cancellables)
    $operationPhase
      .removeDuplicates()
      .sink { [weak self] phase in
        guard let self else {
          return
        }
        hud.providerName = providerName
        hud.polishesOnDevice = settingsStore.settings.refinementRoute == .onDevice
        hud.detail = hudDetail()
        let previous = hud.phase
        hud.phase = phase
        guard settingsStore.settings.soundFeedback else {
          return
        }
        if phase == .recording, previous != .recording {
          SoundFeedback.started()
        } else if case .failed = phase {
          SoundFeedback.failed()
        }
      }
      .store(in: &cancellables)
  }

  /// Delivers live preview text to the HUD, or nil when live preview is off.
  private func partialsHandler() -> (@Sendable (String) -> Void)? {
    guard settingsStore.settings.livePreview else {
      return nil
    }
    return { [weak self] text in
      Task { @MainActor in
        self?.livePartial = text
      }
    }
  }

  /// The qualifier the HUD shows beside the mode: the tone MicAI will write in
  /// for dictation, the destination language for Translate.
  private func hudDetail() -> String? {
    let settings = settingsStore.settings
    switch operationMode {
    case .dictation:
      guard settings.refinementRoute != nil else {
        return nil
      }
      let tone = settings.resolver().tone(for: operationTarget)
      if let name = operationTarget?.applicationName {
        return "\(tone.displayName), for \(name)"
      }
      return tone.displayName
    case .translate:
      return "to \(settings.translationTargetLanguage)"
    case .custom:
      return operationCustomMode?.name
    case .command:
      return nil
    case .ask:
      return nil
    case nil:
      return nil
    }
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

  private func handleHotkey(binding: HotkeyBindingID, action: HotkeyAction) {
    switch binding {
    case .mode(let mode):
      handleHotkey(mode: mode, action: action)
    case .custom(let id):
      if action == .startRecording {
        pendingCustomModeID = id
      }
      handleHotkey(mode: .custom, action: action)
    }
  }

  private func handleHotkey(mode: MicAIMode, action: HotkeyAction) {
    if action == .stopRecording, operationStartupMode == mode {
      pendingStopMode = mode
      return
    }

    if action == .lockRecording {
      isHandsFree = true
      return
    }

    Task {
      switch (mode, action) {
      case (_, .lockRecording):
        break
      case (.dictation, .startRecording):
        await startDictation()
      case (.dictation, .stopRecording):
        await finishDictation()
      case (.dictation, .cancelRecording):
        await cancelDictation()
      case (.command, .startRecording), (.translate, .startRecording),
        (.ask, .startRecording), (.custom, .startRecording):
        await discardDictationStartedByChord()
        await startSelectionMode(mode)
      case (.command, .stopRecording):
        await finishCommand()
      case (.translate, .stopRecording):
        await finishTranslate()
      case (.ask, .stopRecording):
        await finishAsk()
      case (.custom, .stopRecording):
        await finishCustom()
      case (.command, .cancelRecording), (.translate, .cancelRecording),
        (.ask, .cancelRecording), (.custom, .cancelRecording):
        await cancelSelectionMode(mode)
      }
    }
  }

  /// Right Option is also the right-hand ⌥ of every ⌥-chord, so typing, say,
  /// ⌃⌥Space with it starts a dictation a moment before the command chord
  /// completes. When that happens the dictation was never intended: drop it
  /// without a "Cancelled" notice and let the chord's mode start.
  private func discardDictationStartedByChord() async {
    guard settingsStore.settings.dictationHotkey == .rightOption,
      operationMode == .dictation,
      operationPhase == .recording,
      let operationID
    else {
      return
    }
    await pipeline.cancel(operationID: operationID)
    hotkeyMonitor.reset(mode: .dictation)
    operationPhase = .idle
    inputLevel = 0
    clearOperation()
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
        },
        partials: partialsHandler()
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

      let settings = settingsStore.settings
      if settings.refinementRoute != nil,
        await coordinator.markAwaitingLLM(operationID: operationID)
      {
        operationPhase = .awaitingLLM
      }

      // Never throws: on any refinement failure this returns the raw
      // transcript, so a network problem costs polish, not the dictation.
      // Registered with the coordinator so Esc also stops the codex child
      // that refinement may be waiting on.
      let composer = self.composer
      let composeTask = Task {
        await composer.compose(
          transcript: transcript,
          mode: .dictation,
          target: target,
          settings: settings
        )
      }
      guard
        await coordinator.registerCancellationHandler(
          { composeTask.cancel() },
          operationID: operationID
        )
      else {
        throw MicAIError.cancelled
      }
      let composed = await composeTask.value
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      await refreshStoredCollections()

      guard await coordinator.markInserting(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      operationPhase = .inserting
      insertionRecovery.prepare(composed.text)
      accessibilityPermission.refresh()
      guard accessibilityPermission.isTrusted else {
        throw MicAIError.accessibilityDenied
      }

      do {
        let coordinator = self.coordinator
        try await insertionCoordinator.apply(
          .insert(composed.text),
          to: target,
          while: {
            await coordinator.isCurrent(operationID: operationID)
          }
        )
      } catch let error as MicAIError where error == .clipboardChanged {
        guard await coordinator.complete(operationID: operationID) else {
          throw MicAIError.cancelled
        }
        await recordDictationHistory(composed)
        complete(composed: composed, diagnostic: error.localizedDescription)
        return
      }

      guard await coordinator.complete(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      await recordDictationHistory(composed)
      complete(composed: composed)
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
      errorMessage = failureMessage(for: micAIError)
      operationPhase = .failed(micAIError)
      clearOperation()
    }
  }

  /// Only after the text went in, so History never lists a dictation that was
  /// cancelled or failed to insert.
  private func recordDictationHistory(_ composed: ComposedDictation) async {
    await composer.recordHistory(for: composed)
    await refreshStoredCollections()
  }

  private func cancelDictation() async {
    guard let operationID else {
      return
    }
    await pipeline.cancel(operationID: operationID)
    acknowledgeCancellation(mode: .dictation)
  }

  /// Returns to idle, then briefly shows "Cancelled" in the HUD so an Esc press
  /// gets visible confirmation that nothing was inserted.
  private func acknowledgeCancellation(mode: MicAIMode) {
    MicAITelemetry.operationCancelled(mode: mode)
    operationPhase = .idle
    errorMessage = nil
    inputLevel = 0
    clearOperation()
    let hud = hudController.model
    hud.mode = mode
    hud.message = "Nothing was inserted"
    hud.phase = .failed(.cancelled)
  }

  /// Shared preamble for AI Commands, AI Translate and Ask AI.
  ///
  /// The three differ only in what happens after the transcript exists, so the
  /// gates, permission checks and target capture live here once. Keeping three
  /// near-identical copies is how one of them ends up missing a check.
  private func startSelectionMode(_ mode: MicAIMode) async {
    guard operationID == nil, operationAttemptID == nil else {
      hotkeyMonitor.reset(mode: mode)
      return
    }
    let attemptID = UUID()
    operationAttemptID = attemptID
    let commandSettings = settingsStore.settings
    operationStartupMode = mode
    if mode == .custom {
      operationCustomMode = pendingCustomModeID.flatMap {
        settingsStore.settings.customMode(id: $0)
      }
      pendingCustomModeID = nil
    }
    guard isActive(mode) else {
      rejectStart(mode: mode, with: startBlocker(for: mode))
      clearOperation(ifAttemptID: attemptID)
      return
    }
    // Checked before recording so the user is not asked to speak, and their
    // clipboard is not round-tripped, for a command that cannot run.
    guard codexCLIAvailable else {
      rejectStart(mode: mode, with: .codexCLIUnavailable)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    guard modelState == .ready else {
      rejectStart(mode: mode, with: .asrNotInitialized)
      clearOperation(ifAttemptID: attemptID)
      return
    }

    microphonePermission.refresh()
    guard microphonePermission.isGranted else {
      rejectStart(mode: mode, with: .microphoneDenied)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    accessibilityPermission.refresh()
    guard accessibilityPermission.isTrusted else {
      rejectStart(mode: mode, with: .accessibilityDenied)
      clearOperation(ifAttemptID: attemptID)
      return
    }
    guard let target = await targetTracker.capture() else {
      rejectStart(mode: mode, with: .targetChanged)
      clearOperation(ifAttemptID: attemptID)
      return
    }

    do {
      errorMessage = nil
      lastTranscript = nil
      let appModel = self
      let coordinator = self.coordinator
      _ = try await commandPipeline.begin(
        mode: mode,
        target: target,
        model: commandSettings.llmModel,
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
            appModel.operationMode = mode
            appModel.operationTarget = target
            appModel.operationPhase = .recording
            return true
          }
          if !accepted {
            await coordinator.cancel(operationID: operationID)
          }
        },
        partials: partialsHandler()
      )
      guard operationAttemptID == attemptID else {
        return
      }
      operationStartupMode = nil
      if pendingStopMode == mode {
        pendingStopMode = nil
        await finishSelectionMode(mode)
      }
    } catch {
      await targetTracker.release(target)
      guard operationAttemptID == attemptID else {
        return
      }
      if error as? MicAIError == .cancelled {
        clearOperation(ifAttemptID: attemptID)
        hotkeyMonitor.reset(mode: mode)
        return
      }
      let micAIError = (error as? MicAIError) ?? .insertionFailed
      errorMessage = failureMessage(for: micAIError)
      operationPhase = .failed(micAIError)
      clearOperation(ifAttemptID: attemptID)
      hotkeyMonitor.reset(mode: mode)
    }
  }

  private func finishTranslate() async {
    let engine = translationEngine
    let language = settingsStore.settings.translationTargetLanguage
    await runSelectionInsertion(mode: .translate) { spokenText, selectedText, model in
      try await engine.translate(
        spokenText: spokenText,
        selectedText: selectedText,
        targetLanguage: language,
        model: model
      )
    }
  }

  private func finishAsk() async {
    guard let operationID, let target = operationTarget else {
      return
    }
    guard await isStillActive(.ask) else {
      return
    }

    operationPhase = .transcribing
    inputLevel = 0
    do {
      let appModel = self
      let engine = askEngine
      let model = settingsStore.settings.llmModel
      let alwaysWindow = settingsStore.settings.askAlwaysOpensWindow
      let produced = try await commandPipeline.finish(
        operationID: operationID,
        awaitingLLM: {
          await MainActor.run { appModel.operationPhase = .awaitingLLM }
        },
        produce: { spokenText, selectedText in
          try await engine.ask(
            question: spokenText,
            selectedText: selectedText,
            model: model,
            alwaysOpensWindow: alwaysWindow
          )
        }
      )
      let result = produced.value

      // An answer bound for the window never touches the target application, so
      // it skips insertion entirely -- and with it the Accessibility check and
      // the clipboard round trip.
      if result.destination == .answerWindow {
        guard await coordinator.markInserting(operationID: operationID) else {
          throw MicAIError.cancelled
        }
        guard await coordinator.complete(operationID: operationID) else {
          throw MicAIError.cancelled
        }
        await recordSelectionHistory(
          mode: .ask,
          spoken: produced.instruction,
          output: result.answer,
          target: target
        )
        pendingAnswer = AskAnswer(
          question: result.question,
          answer: result.answer,
          usedSelection: result.usedSelection
        )
        lastResult = result.answer
        complete(transcript: produced.instruction)
        return
      }

      try await insert(
        result.insertionIntent,
        operationID: operationID,
        target: target,
        mode: .ask,
        spoken: produced.instruction,
        output: result.answer
      )
    } catch {
      await failSelectionMode(operationID: operationID, error: error)
    }
  }

  /// Runs the custom mode captured at start: insert it, or show it in the
  /// answer window without touching the document.
  private func finishCustom() async {
    guard let operationID, let target = operationTarget, let mode = operationCustomMode else {
      return
    }
    guard await isStillActive(.custom) else {
      return
    }

    operationPhase = .transcribing
    inputLevel = 0
    do {
      let appModel = self
      let engine = customModeEngine
      let model = settingsStore.settings.llmModel
      let produced = try await commandPipeline.finish(
        operationID: operationID,
        worksOnSelectionAlone: true,
        awaitingLLM: {
          await MainActor.run { appModel.operationPhase = .awaitingLLM }
        },
        produce: { spokenText, selectedText in
          try await engine.run(
            mode,
            spokenText: spokenText,
            selectedText: selectedText,
            model: model
          )
        }
      )
      let result = produced.value

      guard result.output == .window else {
        try await insert(
          result.insertionIntent,
          operationID: operationID,
          target: target,
          mode: .custom,
          spoken: produced.instruction,
          output: result.text
        )
        return
      }
      guard await coordinator.markInserting(operationID: operationID),
        await coordinator.complete(operationID: operationID)
      else {
        throw MicAIError.cancelled
      }
      await recordSelectionHistory(
        mode: .custom,
        spoken: produced.instruction,
        output: result.text,
        target: target
      )
      var usedSelection = false
      if case .replaceSelection = result.insertionIntent {
        usedSelection = true
      }
      pendingAnswer = AskAnswer(
        question: produced.instruction.text,
        answer: result.text,
        usedSelection: usedSelection,
        modeName: mode.name
      )
      lastResult = result.text
      complete(transcript: produced.instruction)
    } catch {
      await failSelectionMode(operationID: operationID, error: error)
    }
  }

  /// Shared tail for the modes that end in an insertion: transcribe, transform,
  /// insert, record history.
  private func runSelectionInsertion(
    mode: MicAIMode,
    produce: @escaping @Sendable (String, String?, String) async throws -> InsertionIntent
  ) async {
    guard let operationID, let target = operationTarget else {
      return
    }
    guard await isStillActive(mode) else {
      return
    }

    operationPhase = .transcribing
    inputLevel = 0
    do {
      let appModel = self
      let model = settingsStore.settings.llmModel
      let produced = try await commandPipeline.finish(
        operationID: operationID,
        worksOnSelectionAlone: mode == .translate,
        awaitingLLM: {
          await MainActor.run { appModel.operationPhase = .awaitingLLM }
        },
        produce: { spokenText, selectedText in
          try await produce(spokenText, selectedText, model)
        }
      )

      try await insert(
        produced.value,
        operationID: operationID,
        target: target,
        mode: mode,
        spoken: produced.instruction,
        output: produced.value.text
      )
    } catch {
      await failSelectionMode(operationID: operationID, error: error)
    }
  }

  private func insert(
    _ intent: InsertionIntent,
    operationID: UUID,
    target: TargetIdentity,
    mode: MicAIMode,
    spoken: Transcript,
    output: String
  ) async throws {
    guard await coordinator.markInserting(operationID: operationID) else {
      throw MicAIError.cancelled
    }
    operationPhase = .inserting
    insertionRecovery.prepare(output)
    accessibilityPermission.refresh()
    guard accessibilityPermission.isTrusted else {
      throw MicAIError.accessibilityDenied
    }

    var diagnostic: String?
    do {
      let coordinator = self.coordinator
      try await insertionCoordinator.apply(
        intent,
        to: target,
        while: { await coordinator.isCurrent(operationID: operationID) }
      )
    } catch let error as MicAIError where error == .clipboardChanged {
      diagnostic = error.localizedDescription
    }

    guard await coordinator.complete(operationID: operationID) else {
      throw MicAIError.cancelled
    }
    providerStatus = .readyToAttempt
    lastResult = output
    await recordSelectionHistory(
      mode: mode,
      spoken: spoken,
      output: output,
      target: target
    )
    complete(transcript: spoken, diagnostic: diagnostic)
  }

  private func failSelectionMode(operationID: UUID, error: Error) async {
    let micAIError = (error as? MicAIError) ?? .llmServerFailure
    if micAIError == .cancelled, !(await coordinator.isCurrent(operationID: operationID)) {
      return
    }
    providerStatus = .failed(micAIError)
    if await coordinator.isCurrent(operationID: operationID) {
      _ = await coordinator.fail(operationID: operationID, error: micAIError)
    }
    errorMessage = failureMessage(for: micAIError)
    operationPhase = .failed(micAIError)
    clearOperation()
  }

  private func recordSelectionHistory(
    mode: MicAIMode,
    spoken: Transcript,
    output: String,
    target: TargetIdentity
  ) async {
    guard settingsStore.settings.historyEnabled else {
      return
    }
    await historyStore.record(
      HistoryEntry(
        mode: mode,
        modeName: mode == .custom ? operationCustomMode?.name : nil,
        rawTranscript: spoken.text,
        finalText: output,
        applicationName: target.applicationName,
        bundleIdentifier: target.bundleIdentifier,
        audioDuration: spoken.audioDuration,
        refined: true
      )
    )
    await refreshStoredCollections()
  }

  private func finishSelectionMode(_ mode: MicAIMode) async {
    switch mode {
    case .command:
      await finishCommand()
    case .translate:
      await finishTranslate()
    case .ask:
      await finishAsk()
    case .custom:
      await finishCustom()
    case .dictation:
      await finishDictation()
    }
  }

  private func isActive(_ mode: MicAIMode) -> Bool {
    switch mode {
    case .dictation:
      true
    case .command:
      settingsStore.settings.areCommandsActive
    case .translate:
      settingsStore.settings.isTranslateActive
    case .ask:
      settingsStore.settings.isAskActive
    case .custom:
      settingsStore.settings.areCustomModesActive && operationCustomMode != nil
    }
  }

  /// The most specific reason a mode is unavailable, so the HUD says something
  /// the user can act on rather than a generic service failure.
  private func startBlocker(for mode: MicAIMode) -> MicAIError {
    let settings = settingsStore.settings
    if settings.privacyMode {
      return .llmForbidden
    }
    if mode == .translate,
      settings.translationTargetLanguage
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return .translationLanguageMissing
    }
    return .llmServerFailure
  }

  private func rejectStart(mode: MicAIMode, with error: MicAIError) {
    errorMessage = error.localizedDescription
    hotkeyMonitor.reset(mode: mode)
  }

  private func finishCommand() async {
    guard let operationID, let target = operationTarget else {
      return
    }
    guard await isStillActive(.command) else {
      return
    }

    operationPhase = .transcribing
    inputLevel = 0
    do {
      let appModel = self
      let result = try await commandPipeline.finish(
        operationID: operationID,
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
      insertionRecovery.prepare(result.intent.text)
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
        lastResult = result.intent.text
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
      lastResult = result.intent.text
      await recordCommandHistory(result: result, target: target)
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
      errorMessage = failureMessage(for: micAIError)
      operationPhase = .failed(micAIError)
      clearOperation()
    }
  }

  /// Stops a network mode that settings no longer allow, and says why.
  private func abandonSelectionMode(_ mode: MicAIMode, reason: MicAIError) async {
    guard operationID != nil, operationMode == mode else {
      return
    }
    await cancelSelectionMode(mode)
    errorMessage = reason.localizedDescription
    operationPhase = .failed(reason)
  }

  /// Checked again when a network mode finishes, for a change that landed
  /// between the key press and the operation starting, where `applySettings`
  /// has nothing to cancel yet. Returns false after abandoning the operation.
  private func isStillActive(_ mode: MicAIMode) async -> Bool {
    guard !isActive(mode) else {
      return true
    }
    await abandonSelectionMode(mode, reason: startBlocker(for: mode))
    return false
  }

  private func cancelSelectionMode(_ mode: MicAIMode) async {
    guard let operationID else {
      return
    }
    hotkeyMonitor.reset(mode: mode)
    await commandPipeline.cancel(operationID: operationID)
    acknowledgeCancellation(mode: mode)
  }

  private func complete(transcript: Transcript, diagnostic: String? = nil) {
    lastTranscript = transcript.text
    errorMessage = diagnostic
    playFinishedSound()
    operationPhase = .idle
    clearOperation()
  }

  private func complete(composed: ComposedDictation, diagnostic: String? = nil) {
    lastTranscript = composed.text
    lastResult = composed.text
    lastTone = composed.tone
    playFinishedSound()
    // A refinement failure is worth surfacing, but it must not mask a real
    // insertion diagnostic, which is the more actionable of the two.
    errorMessage = diagnostic ?? composed.refinementFailure?.localizedDescription
    operationPhase = .idle
    clearOperation()
  }

  private func playFinishedSound() {
    if settingsStore.settings.soundFeedback {
      SoundFeedback.finished()
    }
  }

  // MARK: - History and vocabulary

  /// Commands share the history list with dictation, so "where did that text
  /// go" has one place to look rather than two.
  private func recordCommandHistory(
    result: CommandResult,
    target: TargetIdentity
  ) async {
    guard settingsStore.settings.historyEnabled else {
      return
    }

    await historyStore.record(
      HistoryEntry(
        mode: .command,
        rawTranscript: result.instruction.text,
        finalText: result.intent.text,
        applicationName: target.applicationName,
        bundleIdentifier: target.bundleIdentifier,
        audioDuration: result.instruction.audioDuration,
        refined: true
      )
    )
    await refreshStoredCollections()
  }

  private func loadStoredCollections() async {
    await vocabularyStore.load()
    await historyStore.load()
    await snippetStore.load()
    await refreshStoredCollections()
  }

  private func refreshStoredCollections() async {
    historyEntries = await historyStore.all()
    vocabularyEntries = await vocabularyStore.all()
    snippetEntries = await snippetStore.all()
  }

  /// Saves a user edit from the history list and learns the terms it implies.
  func correctHistoryEntry(id: UUID, to correctedText: String) {
    Task { @MainActor in
      await composer.applyCorrection(historyEntryID: id, correctedText: correctedText)
      await refreshStoredCollections()
    }
  }

  func deleteHistoryEntry(id: UUID) {
    Task { @MainActor in
      await historyStore.delete(entryID: id)
      await refreshStoredCollections()
    }
  }

  func clearHistory() {
    Task { @MainActor in
      await historyStore.clear()
      await refreshStoredCollections()
    }
  }

  func upsertVocabularyEntry(heard: String, written: String) {
    Task { @MainActor in
      await vocabularyStore.upsert(VocabularyEntry(heard: heard, written: written))
      await refreshStoredCollections()
    }
  }

  func deleteVocabularyEntry(id: UUID) {
    Task { @MainActor in
      await vocabularyStore.delete(entryID: id)
      await refreshStoredCollections()
    }
  }

  func upsertSnippet(trigger: String, text: String) {
    Task { @MainActor in
      await snippetStore.upsert(Snippet(trigger: trigger, text: text))
      await refreshStoredCollections()
    }
  }

  func deleteSnippet(id: UUID) {
    Task { @MainActor in
      await snippetStore.delete(snippetID: id)
      await refreshStoredCollections()
    }
  }

  /// The error to show, plus where to find finished text that could not be
  /// inserted. Keeping it is the point: a focus change or a missing
  /// permission must not cost the user a dictation or a model answer.
  private func failureMessage(for error: MicAIError) -> String {
    let outcome = insertionRecovery.outcome(for: error)
    if let kept = outcome.keptText {
      lastResult = kept
      MicAITelemetry.resultHeldForRecovery(mode: operationMode ?? .dictation)
    }
    return outcome.message
  }

  private func clearOperation(ifAttemptID expectedAttemptID: UUID? = nil) {
    if let expectedAttemptID, operationAttemptID != expectedAttemptID {
      return
    }
    insertionRecovery.reset()
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
    isHandsFree = false
    livePartial = nil
    operationCustomMode = nil
    applyDeferredSpeechModel()
  }

  private func applyDeferredSpeechModel() {
    if let deferredSpeechModel {
      switchSpeechModelIfNeeded(to: deferredSpeechModel)
    }
  }

  private func rejectDictationStart(with error: MicAIError) {
    errorMessage = error.localizedDescription
    hotkeyMonitor.reset(mode: .dictation)
  }

  private func cancelActiveOperation() async {
    guard operationID != nil || operationAttemptID != nil else {
      return
    }
    // Once insertion starts the paste may already be delivered, so a late Esc
    // would report "Cancelled" for text that is in the document. The HUD
    // stops offering Esc in this phase for the same reason.
    guard operationPhase != .inserting else {
      return
    }
    guard operationID != nil else {
      operationAttemptID = nil
      operationPhase = .idle
      inputLevel = 0
      resetAllHotkeys()
      applyDeferredSpeechModel()
      return
    }
    switch operationMode {
    case .dictation:
      await cancelDictation()
    case .command, .translate, .ask, .custom:
      await cancelSelectionMode(operationMode ?? .command)
    case nil:
      return
    }
    resetAllHotkeys()
  }

  /// Resets every mode rather than naming them: Esc and an aborted start clear
  /// the whole keyboard, and a list here is one more place to forget a mode.
  private func resetAllHotkeys() {
    for mode in MicAIMode.allCases {
      hotkeyMonitor.reset(mode: mode)
    }
  }

  /// Configured means a model is set, the chosen provider has what it needs
  /// to sign in, and something uses it: clean-up, Command, Translate, Ask AI
  /// or a custom mode. Not the Command shortcut alone, since any of those
  /// sends requests through the same provider.
  private func refreshProviderStatus() {
    let settings = settingsStore.settings
    let usesProvider =
      settings.refinementRoute == .languageModel
      || settings.commandHotkey != nil
      || settings.translateHotkey != nil
      || settings.askHotkey != nil
      || !settings.customModes.isEmpty

    if !usesProvider {
      providerStatus = .notConfigured
    } else if !codexCLIAvailable {
      providerStatus = .failed(.codexCLIUnavailable)
    } else {
      providerStatus = .readyToAttempt
    }
  }
}

private final class ProviderStatusRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable (ProviderStatus) -> Void)?
  private var usageHandler: (@Sendable (LLMUsageReport) -> Void)?

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

  func setUsageHandler(_ handler: @escaping @Sendable (LLMUsageReport) -> Void) {
    lock.withLock { usageHandler = handler }
  }

  func sendUsage(_ report: LLMUsageReport) {
    let handler = lock.withLock { usageHandler }
    handler?(report)
  }
}
