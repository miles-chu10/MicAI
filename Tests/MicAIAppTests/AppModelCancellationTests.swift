import Foundation
import MicAICore
import Testing
@testable import MicAI

@Suite
@MainActor
struct AppModelCancellationTests {
  @Test
  func staleDictationCallbacksCannotAffectRestartedDictation() async throws {
    try await expectStaleRecordingCallbacksAreIgnored(mode: .dictation)
  }

  @Test
  func staleCommandCallbacksCannotAffectRestartedCommand() async throws {
    try await expectStaleRecordingCallbacksAreIgnored(mode: .command)
  }

  @Test
  func hudModeTracksOperationIdentityAcrossStartCancelAndRestart() async throws {
    let appModel = AppModel(startRuntime: false)
    let dictationID = try await appModel.beginOperationForTesting(mode: .dictation)
    #expect(appModel.hudMode == .dictation)

    await appModel.cancelOperationForTesting(operationID: dictationID)
    #expect(appModel.hudMode == nil)

    let commandID = try await appModel.beginOperationForTesting(mode: .command)
    #expect(appModel.hudMode == .command)

    await appModel.cancelOperationForTesting(operationID: commandID)
    #expect(appModel.hudMode == nil)
  }

  @Test
  func popupPresentationDistinguishesDictationAndCommandPhases() {
    let dictation = RecordingHUDPresentation(
      mode: .dictation,
      phase: .recording,
      message: nil
    )
    #expect(dictation.title == "Dictating")
    #expect(dictation.status == "Listening")
    #expect(dictation.modeIcon == "mic.fill")
    #expect(dictation.canCancel)

    let command = RecordingHUDPresentation(
      mode: .command,
      phase: .awaitingLLM,
      message: nil
    )
    #expect(command.title == "AI Command")
    #expect(command.status == "Applying your command")
    #expect(command.modeIcon == "sparkles")
    #expect(command.canCancel)

    let proof = RecordingHUDPresentation(
      mode: .command,
      phase: .inserting,
      message: nil
    )
    #expect(proof.status == "Preparing proof")
    #expect(!proof.canCancel)

    let failure = RecordingHUDPresentation(
      mode: .dictation,
      phase: .failed(.targetChanged),
      message: "The target changed."
    )
    #expect(failure.status == "The target changed.")
    #expect(!failure.canCancel)
  }

  @Test
  func commandPreparingProofPhaseIsReachableAfterProviderCompletion() async throws {
    let appModel = AppModel(startRuntime: false)
    let operationID = try await appModel.beginCommandOperationForTesting()

    try await appModel.markCommandPreparingProofForTesting(
      operationID: operationID
    )

    #expect(appModel.hudMode == .command)
    #expect(appModel.operationPhase == .inserting)
    let presentation = RecordingHUDPresentation(
      mode: appModel.hudMode,
      phase: appModel.operationPhase,
      message: appModel.errorMessage
    )
    #expect(presentation.status == "Preparing proof")
    #expect(!presentation.canCancel)
  }

  @Test
  func oppositeModeRejectionReplacesThePreviousFailureHUDIdentity() async throws {
    let appModel = AppModel(startRuntime: false)
    let operationID = try await appModel.beginOperationForTesting(mode: .dictation)
    await appModel.applyLateFinishErrorForTesting(
      operationID: operationID,
      mode: .dictation,
      error: .targetChanged
    )
    #expect(appModel.hudMode == .dictation)

    appModel.rejectStartForTesting(mode: .command, error: .asrNotInitialized)

    #expect(appModel.hudMode == .command)
    #expect(appModel.operationPhase == .failed(.asrNotInitialized))
  }

  @Test
  func commandCancellationRestoresConfiguredIdleProviderStatus() async throws {
    let appModel = AppModel(startRuntime: false)
    let operationID = try await appModel.beginOperationForTesting(mode: .command)
    await appModel.sendProviderStatusForTesting(
      requestID: operationID,
      status: .retryingCredential
    )
    #expect(appModel.providerStatus == .retryingCredential)

    await appModel.cancelCommandOperationForTesting(operationID: operationID)

    #expect(appModel.providerStatus == .notConfigured)
    #expect(appModel.operationPhase == .idle)
    #expect(appModel.hudMode == nil)
  }

  @Test
  func staleCommandProviderStatusCannotOverwriteRestartedCommand() async throws {
    let appModel = AppModel(startRuntime: false)
    let oldOperationID = try await appModel.beginOperationForTesting(mode: .command)

    await appModel.sendProviderStatusForTesting(
      requestID: oldOperationID,
      status: .retryingCredential
    )
    #expect(appModel.providerStatus == .retryingCredential)

    await appModel.cancelOperationForTesting(operationID: oldOperationID)
    let newOperationID = try await appModel.beginOperationForTesting(mode: .command)
    await appModel.sendProviderStatusForTesting(
      requestID: newOperationID,
      status: .retryingCredential
    )

    await appModel.sendProviderStatusForTesting(
      requestID: oldOperationID,
      status: .failed(.cancelled)
    )
    #expect(appModel.providerStatus == .retryingCredential)
    #expect(appModel.operationIDForTesting == newOperationID)

    await appModel.sendProviderStatusForTesting(
      requestID: newOperationID,
      status: .readyToAttempt
    )
    #expect(appModel.providerStatus == .readyToAttempt)
    await appModel.cancelOperationForTesting(operationID: newOperationID)
  }

  @Test
  func staleDictationProviderStatusCannotOverwriteRestartedDictation() async throws {
    let appModel = AppModel(startRuntime: false)
    let oldOperationID = try await appModel.beginOperationForTesting(mode: .dictation)
    appModel.sendDictationProviderStatusForTesting(
      requestID: oldOperationID,
      status: .transcribing(.openAI)
    )
    #expect(appModel.dictationProviderStatus == .transcribing(.openAI))

    await appModel.cancelOperationForTesting(operationID: oldOperationID)
    let newOperationID = try await appModel.beginOperationForTesting(mode: .dictation)
    appModel.sendDictationProviderStatusForTesting(
      requestID: newOperationID,
      status: .transcribing(.parakeet)
    )
    appModel.sendDictationProviderStatusForTesting(
      requestID: oldOperationID,
      status: .failed(.openAI, .transcriptionServerFailure)
    )

    #expect(appModel.dictationProviderStatus == .transcribing(.parakeet))
    #expect(appModel.operationIDForTesting == newOperationID)
    await appModel.cancelOperationForTesting(operationID: newOperationID)
  }

  @Test
  func providerSettingsStayNonNetworkingStableAndTruthful() async throws {
    let suiteName = "MicAIAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let keyProvider = CountingOpenAIAPIKeyProvider()
    let transport = CountingOpenAITranscriptionTransport()
    let appModel = AppModel(
      startRuntime: false,
      settingsDefaults: defaults,
      openAIAPIKeyProvider: keyProvider,
      openAITranscriptionTransport: transport
    )
    var settings = appModel.settingsStore.settings
    settings.dictationProvider = .openAI
    settings.openAITranscriptionModel = "gpt-transcribe"
    settings.openAITranscriptionFallbackEnabled = true

    #expect(appModel.settingsStore.save(settings))
    appModel.applySettings()

    #expect(await keyProvider.accessCount == 0)
    #expect(await transport.performCount == 0)
    #expect(
      appModel.dictationProviderStatus
        == .openAINotConfigured(fallbackEnabled: true, fallbackReady: false)
    )

    try await expectActiveRecordingDefersSettingsApplication(activeMode: .hold)
    try await expectActiveRecordingDefersSettingsApplication(activeMode: .toggle)
    try await expectOpenAIFallbackPresentationTracksEffectiveReadiness()
  }

  private func expectOpenAIFallbackPresentationTracksEffectiveReadiness() async throws {
    let suiteName = "MicAIAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let appModel = AppModel(startRuntime: false, settingsDefaults: defaults)
    var settings = appModel.settingsStore.settings
    settings.dictationProvider = .openAI
    settings.openAITranscriptionFallbackEnabled = true
    #expect(appModel.settingsStore.save(settings))
    appModel.applySettings()

    appModel.setModelStateForTesting(.notDownloaded)
    #expect(appModel.dictationSelectedRouteLabel == "OpenAI — gpt-transcribe")
    #expect(
      appModel.dictationShortcutDetail
        == "Hold to dictate • Effective: Blocked — Parakeet fallback not prepared"
    )
    #expect(appModel.dictationPrivacyDetail.contains("fallback is not prepared"))
    #expect(!appModel.dictationPrivacyDetail.contains("effective on-device route"))

    appModel.setModelStateForTesting(.ready)
    #expect(
      appModel.dictationShortcutDetail
        == "Hold to dictate • Effective: Parakeet fallback — OpenAI not configured"
    )
    #expect(appModel.dictationPrivacyDetail.contains("effective on-device route"))
  }

  @Test
  func lateDictationErrorDoesNotEraseRestartedOperation() async throws {
    let appModel = AppModel(startRuntime: false)
    let cancelledOperationID = try await appModel.beginOperationForTesting(
      mode: .dictation
    )

    await appModel.cancelOperationForTesting(operationID: cancelledOperationID)
    let nextOperationID = try await appModel.beginOperationForTesting(mode: .dictation)

    await appModel.applyLateFinishErrorForTesting(
      operationID: cancelledOperationID,
      mode: .dictation,
      error: .targetChanged
    )

    #expect(appModel.operationIDForTesting == nextOperationID)
    #expect(appModel.isOperationActive)
    #expect(!appModel.isFinishingOperationForTesting)
    #expect(appModel.operationPhase == .recording)
    #expect(appModel.errorMessage == nil)
    await appModel.cancelOperationForTesting(operationID: nextOperationID)
  }

  @Test
  func lateCommandErrorDoesNotEraseRestartedOperation() async throws {
    let appModel = AppModel(startRuntime: false)
    let cancelledOperationID = try await appModel.beginOperationForTesting(
      mode: .command
    )

    await appModel.cancelOperationForTesting(operationID: cancelledOperationID)
    let nextOperationID = try await appModel.beginOperationForTesting(mode: .command)

    await appModel.applyLateFinishErrorForTesting(
      operationID: cancelledOperationID,
      mode: .command,
      error: .llmServerFailure
    )

    #expect(appModel.operationIDForTesting == nextOperationID)
    #expect(appModel.isOperationActive)
    #expect(!appModel.isFinishingOperationForTesting)
    #expect(appModel.operationPhase == .recording)
    #expect(appModel.errorMessage == nil)
    await appModel.cancelOperationForTesting(operationID: nextOperationID)
  }

  @Test
  func transportCancellationAllowsImmediateNextRecording() async throws {
    let appModel = AppModel(startRuntime: false)
    let cancelledOperationID = try await appModel.beginCommandOperationForTesting()

    await appModel.finishCommandWithTransportCancellationForTesting(
      operationID: cancelledOperationID
    )

    #expect(!appModel.isOperationActive)
    #expect(!appModel.isFinishingOperationForTesting)
    #expect(appModel.operationPhase == .idle)

    let nextOperationID = try await appModel.beginCommandOperationForTesting()
    #expect(nextOperationID != cancelledOperationID)
    await appModel.cancelOperationForTesting(operationID: nextOperationID)
  }

  @Test
  func proofTargetFailurePreservesTheSameRecoverableDraft() async throws {
    let appModel = AppModel(startRuntime: false)
    appModel.installProofFixtureForTesting()
    let original = try #require(appModel.pendingProofDraft)

    await appModel.approveProofFixtureForTesting()

    let retained = try #require(appModel.pendingProofDraft)
    #expect(retained.id == original.id)
    #expect(retained.proposedText == original.proposedText)
    #expect(retained.state == .targetUnavailable)
    #expect(appModel.readiness.command.hasPendingRecovery)
    #expect(appModel.operationPhase == .failed(.targetChanged))
  }

  @Test
  func proofSelectionMustMatchTheReviewedSourceExactly() {
    let draft = ProofCarryingDraft.transformation(
      instruction: "Make this concise",
      sourceText: "Exact selected text\n",
      proposedText: "Exact proposal\n",
      targetLabel: "Editor"
    )
    let replacement = PendingProofDraftContext(
      draft: draft,
      intent: .replaceSelection(draft.proposedText),
      target: TargetIdentity(processIdentifier: 42),
      fixtureFailure: nil
    )
    let insertion = PendingProofDraftContext(
      draft: draft,
      intent: .insert(draft.proposedText),
      target: TargetIdentity(processIdentifier: 42),
      fixtureFailure: nil
    )

    #expect(replacement.matchesCurrentSelection("Exact selected text\n"))
    #expect(!replacement.matchesCurrentSelection("Changed selected text\n"))
    #expect(!replacement.matchesCurrentSelection("Exact selected text"))
    #expect(insertion.matchesCurrentSelection(nil))
  }

  @Test
  func nonTargetProofFailureKeepsAnAccurateRetryState() async throws {
    let appModel = AppModel(startRuntime: false)
    appModel.installProofFixtureForTesting(failure: .accessibilityDenied)

    await appModel.approveProofFixtureForTesting()

    let retained = try #require(appModel.pendingProofDraft)
    #expect(retained.state == .approvalFailed)
    #expect(retained.notice?.contains("Accessibility access is required") == true)
    #expect(appModel.operationPhase == .failed(.accessibilityDenied))
  }

  @Test
  func postPasteRestoreFailureCannotOfferAutomaticApprovalRetry() async throws {
    let appModel = AppModel(startRuntime: false)
    appModel.installProofFixtureForTesting(
      failure: .clipboardRestoreFailedAfterInsertion
    )

    await appModel.approveProofFixtureForTesting()

    #expect(appModel.pendingProofDraft == nil)
    let uncertain = try #require(appModel.lastProofDraft)
    #expect(uncertain.state == .insertionUncertain)
    #expect(!uncertain.state.isActionable)
    #expect(uncertain.notice?.contains("cannot be retried automatically") == true)
    #expect(appModel.operationPhase == .idle)
  }

  private func expectStaleRecordingCallbacksAreIgnored(
    mode: MicAIMode
  ) async throws {
    let appModel = AppModel(startRuntime: false)
    let oldAttemptID = UUID()
    let oldCallbacks = appModel.recordingCallbacksForTesting(
      mode: mode,
      attemptID: oldAttemptID
    )
    let oldOperationID = try await appModel.beginOperationForTesting(
      mode: mode,
      attemptID: oldAttemptID
    )

    await appModel.cancelOperationForTesting(operationID: oldOperationID)
    let newAttemptID = UUID()
    let newCallbacks = appModel.recordingCallbacksForTesting(
      mode: mode,
      attemptID: newAttemptID
    )
    let newOperationID = try await appModel.beginOperationForTesting(
      mode: mode,
      attemptID: newAttemptID
    )
    await newCallbacks.levels(0.25)

    await oldCallbacks.levels(0.9)
    await oldCallbacks.maximumDurationReached()

    #expect(appModel.operationIDForTesting == newOperationID)
    #expect(appModel.operationPhase == .recording)
    #expect(appModel.inputLevel == 0.25)
    #expect(!appModel.isFinishingOperationForTesting)
    await appModel.cancelOperationForTesting(operationID: newOperationID)
  }

  private func expectActiveRecordingDefersSettingsApplication(
    activeMode: DictationActivationMode
  ) async throws {
    let suiteName = "MicAIAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let appModel = AppModel(startRuntime: false, settingsDefaults: defaults)
    var initialSettings = appModel.settingsStore.settings
    initialSettings.dictationActivationMode = activeMode
    #expect(appModel.settingsStore.save(initialSettings))
    appModel.applySettings()
    #expect(appModel.appliedSettingsCountForTesting == 1)

    let operationID = try await appModel.beginOperationForTesting(mode: .dictation)
    var supersededSettings = initialSettings
    supersededSettings.dictationHotkey = .controlOptionSpace
    #expect(appModel.settingsStore.save(supersededSettings))
    appModel.applySettings()

    var latestSettings = supersededSettings
    latestSettings.dictationHotkey = .commandShiftSpace
    latestSettings.dictationActivationMode = activeMode == .hold ? .toggle : .hold
    #expect(appModel.settingsStore.save(latestSettings))
    appModel.applySettings()

    #expect(appModel.isOperationActive)
    #expect(!appModel.canApplySettings)
    #expect(appModel.deferredSettingsApplicationForTesting)
    #expect(appModel.appliedSettingsForTesting == initialSettings)
    #expect(appModel.appliedSettingsCountForTesting == 1)

    await appModel.cancelOperationForTesting(operationID: operationID)

    #expect(!appModel.isOperationActive)
    #expect(appModel.canApplySettings)
    #expect(!appModel.deferredSettingsApplicationForTesting)
    #expect(appModel.appliedSettingsForTesting == latestSettings)
    #expect(appModel.appliedSettingsCountForTesting == 2)
  }
}

private actor CountingOpenAIAPIKeyProvider: OpenAIAPIKeyProviding {
  private(set) var accessCount = 0

  func apiKey() async throws -> String? {
    accessCount += 1
    return nil
  }
}

private actor CountingOpenAITranscriptionTransport:
  OpenAITranscriptionHTTPTransport
{
  private(set) var performCount = 0

  func perform(
    _ request: URLRequest
  ) async throws -> OpenAITranscriptionHTTPResponse {
    performCount += 1
    return OpenAITranscriptionHTTPResponse(
      statusCode: 500,
      body: Data()
    )
  }
}
