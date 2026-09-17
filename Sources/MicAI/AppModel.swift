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
  /// Tone applied to the most recent dictation, shown in the HUD and history.
  @Published private(set) var lastTone: StyleTone?
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
  private let insertionCoordinator: TextInsertionCoordinator
  private let hudController: RecordingHUDController
  private let providerStatusRelay: ProviderStatusRelay
  private let vocabularyStore: VocabularyStore
  private let historyStore: TranscriptHistoryStore
  private let composer: DictationComposer
  private let translationEngine: TranslationEngine
  private let askEngine: AskEngine
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
    // One client for both paths, so a 401 refresh or a rate-limit status seen
    // by refinement is the same status AI Commands reports.
    let llmClient = ChatGPTResponsesClient(
      credentialLoader: CodexAuthFileLoader(),
      statusHandler: providerStatusRelay.send
    )
    commandPipeline = CommandPipeline(
      dictationPipeline: pipeline,
      commandEngine: CommandEngine(transformer: llmClient),
      insertionCoordinator: insertionCoordinator,
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
    self.vocabularyStore = vocabularyStore
    self.historyStore = historyStore
    composer = DictationComposer(
      refiner: RefinementEngine(transformer: llmClient),
      vocabulary: vocabularyStore,
      history: historyStore
    )
    // Both take their per-call settings as arguments: they run off the main
    // actor inside CommandPipeline, so the values are read on the main actor at
    // the call site and passed down.
    translationEngine = TranslationEngine(transformer: llmClient)
    askEngine = AskEngine(transformer: llmClient)
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
      case (.command, .startRecording), (.translate, .startRecording),
        (.ask, .startRecording):
        await startSelectionMode(mode)
      case (.command, .stopRecording):
        await finishCommand()
      case (.translate, .stopRecording):
        await finishTranslate()
      case (.ask, .stopRecording):
        await finishAsk()
      case (.command, .cancelRecording), (.translate, .cancelRecording),
        (.ask, .cancelRecording):
        await cancelSelectionMode(mode)
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

      let settings = settingsStore.settings
      if settings.isRefinementActive,
        await coordinator.markAwaitingLLM(operationID: operationID)
      {
        operationPhase = .awaitingLLM
      }

      // Never throws: on any refinement failure this returns the raw
      // transcript, so a network problem costs polish, not the dictation.
      let composed = await composer.compose(
        transcript: transcript,
        mode: .dictation,
        target: target,
        settings: settings
      )
      guard await coordinator.isCurrent(operationID: operationID) else {
        throw MicAIError.cancelled
      }
      await refreshStoredCollections()

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
        complete(composed: composed, diagnostic: error.localizedDescription)
        return
      }

      guard await coordinator.complete(operationID: operationID) else {
        throw MicAIError.cancelled
      }
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
    operationStartupMode = mode
    guard isActive(mode) else {
      rejectStart(mode: mode, with: startBlocker(for: mode))
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
        }
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
      errorMessage = micAIError.localizedDescription
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

  /// Shared tail for the modes that end in an insertion: transcribe, transform,
  /// insert, record history.
  private func runSelectionInsertion(
    mode: MicAIMode,
    produce: @escaping @Sendable (String, String?, String) async throws -> InsertionIntent
  ) async {
    guard let operationID, let target = operationTarget else {
      return
    }

    operationPhase = .transcribing
    inputLevel = 0
    do {
      let appModel = self
      let model = settingsStore.settings.llmModel
      let produced = try await commandPipeline.finish(
        operationID: operationID,
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
    errorMessage = micAIError.localizedDescription
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
      errorMessage = micAIError.localizedDescription
      operationPhase = .failed(micAIError)
      clearOperation()
    }
  }

  private func cancelSelectionMode(_ mode: MicAIMode) async {
    guard let operationID else {
      return
    }
    hotkeyMonitor.reset(mode: mode)
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

  private func complete(composed: ComposedDictation, diagnostic: String? = nil) {
    lastTranscript = composed.text
    lastTone = composed.tone
    // A refinement failure is worth surfacing, but it must not mask a real
    // insertion diagnostic, which is the more actionable of the two.
    errorMessage = diagnostic ?? composed.refinementFailure?.localizedDescription
    operationPhase = .idle
    clearOperation()
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
    await refreshStoredCollections()
  }

  private func refreshStoredCollections() async {
    historyEntries = await historyStore.all()
    vocabularyEntries = await vocabularyStore.all()
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

  private func cancelActiveOperation() async {
    guard operationID != nil || operationAttemptID != nil else {
      return
    }
    guard operationID != nil else {
      operationAttemptID = nil
      operationPhase = .idle
      inputLevel = 0
      resetAllHotkeys()
      return
    }
    switch operationMode {
    case .dictation:
      await cancelDictation()
    case .command, .translate, .ask:
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

  private func refreshProviderStatus() {
    let settings = settingsStore.settings
    let configured =
      settings.commandHotkey != nil
      && !settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    providerStatus = configured ? .readyToAttempt : .notConfigured
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
