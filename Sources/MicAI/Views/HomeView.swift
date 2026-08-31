import AppKit
import MicAICore
import SwiftUI

struct OverviewView: View {
  @ObservedObject var appModel: AppModel
  let showSection: (PrimarySection) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HomeHero(appModel: appModel, showSection: showSection)

        if let errorMessage = appModel.errorMessage {
          HomeErrorBanner(
            message: errorMessage,
            reviewSetup: appModel.showOnboarding
          )
        }

        if let draft = appModel.pendingProofDraft {
          HomeProofCallout(draft: draft) {
            showSection(.proof)
          }
        } else if let recovery = appModel.recoverableInsertion {
          RecoveryResultView(appModel: appModel, recovery: recovery)
        }

        HomeWorkflowSection(appModel: appModel, showSection: showSection)

        LocalByDefaultCallout(appModel: appModel)

        SetupReadinessSection(
          appModel: appModel,
          showDictation: { showSection(.dictation) },
          showActivity: {
            showSection(appModel.pendingProofDraft == nil ? .activity : .proof)
          }
        )

        Divider()

        HomePrivacySection(appModel: appModel)

        Divider()

        HomeActivitySection(appModel: appModel, showSection: showSection)
      }
      .padding(28)
      .frame(maxWidth: 940, alignment: .leading)
    }
  }
}

private struct HomeHero: View {
  @ObservedObject var appModel: AppModel
  let showSection: (PrimarySection) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 20) {
          heroIdentity
          Spacer(minLength: 24)
          operationStatus
        }

        VStack(alignment: .leading, spacing: 16) {
          heroIdentity
          operationStatus
        }
      }

      MicAIActionCluster {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) {
            heroActions
          }

          VStack(alignment: .leading, spacing: 10) {
            heroActions
          }
        }
      }

      Text(actionDetail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 16)
        .fill(
          LinearGradient(
            colors: [
              Color.accentColor.opacity(0.20),
              Color(nsColor: .systemTeal).opacity(0.12),
              Color(nsColor: .windowBackgroundColor).opacity(0.72),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    .accessibilityElement(children: .contain)
  }

  private var heroIdentity: some View {
    HStack(alignment: .top, spacing: 18) {
      MicAIWaveformMark()

      VStack(alignment: .leading, spacing: 6) {
        Text("MicAI")
          .font(.headline)
          .foregroundStyle(.tint)

        Text(heroTitle)
          .font(.system(.largeTitle, design: .rounded, weight: .bold))
          .fixedSize(horizontal: false, vertical: true)

        Text(heroSubtitle)
          .font(.title3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var operationStatus: some View {
    VStack(alignment: .trailing, spacing: 6) {
      Text("Live operation")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      StatusPill(phase: appModel.operationPhase)
    }
    .fixedSize()
  }

  @ViewBuilder
  private var heroActions: some View {
    primaryAction
      .controlSize(.large)
      .keyboardShortcut(.defaultAction)
      .micAIPrimaryButtonStyle()

    SettingsLink {
      Label("Settings", systemImage: "gearshape")
    }
    .controlSize(.large)
    .micAISecondaryButtonStyle()
  }

  @ViewBuilder
  private var primaryAction: some View {
    if appModel.readiness.dictation.hasPendingRecovery {
      Button {
        showSection(appModel.pendingProofDraft == nil ? .activity : .proof)
      } label: {
        Label(
          appModel.pendingProofDraft == nil
            ? "Resolve Saved Result" : "Review Proof Draft",
          systemImage: appModel.pendingProofDraft == nil
            ? "doc.badge.clock" : "checkmark.shield"
        )
      }
      .accessibilityHint("Shows retry, copy, and dismiss actions for the saved result.")
    } else if appModel.readiness.dictation.isBusy {
      Button {
      } label: {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(busyActionTitle)
        }
      }
      .disabled(true)
      .accessibilityLabel("MicAI is busy: \(busyActionTitle)")
      .help("Finish or cancel the current operation before starting another.")
    } else if appModel.readiness.dictation.isSetupReady {
      Button {
        showSection(.dictation)
      } label: {
        Label(
          "Dictate with \(appModel.settingsStore.settings.dictationHotkey.displayName)",
          systemImage: "mic.fill"
        )
      }
      .accessibilityHint("Shows dictation instructions and readiness details.")
    } else {
      Button {
        appModel.showOnboarding()
      } label: {
        Label("Finish Setup", systemImage: "checklist")
      }
      .accessibilityHint("Opens the guided MicAI setup checklist.")
    }
  }

  private var heroTitle: String {
    if appModel.readiness.dictation.hasPendingRecovery {
      if appModel.pendingProofDraft != nil {
        return "Approve the result before it can reach another app"
      }
      return "Your result is saved"
    }
    if appModel.readiness.dictation.isBusy {
      return "Turning speech into text"
    }
    return appModel.readiness.dictation.isSetupReady
      ? "Speak where you work" : "Set up private dictation"
  }

  private var heroSubtitle: String {
    if appModel.readiness.dictation.hasPendingRecovery {
      if appModel.pendingProofDraft != nil {
        return "MicAI is withholding transformed text until you review its proof receipt."
      }
      return "MicAI kept the completed text safe for retry or copy."
    }
    if appModel.readiness.dictation.isBusy {
      return "The live status stays visible while MicAI finishes the current operation."
    }
    if appModel.readiness.dictation.isSetupReady {
      return
        "Fast dictation at your cursor, plus AI assistance only when you explicitly ask."
    }
    return
      "Complete the required Mac permissions and transcription route to dictate in any app."
  }

  private var actionDetail: String {
    if appModel.readiness.dictation.hasPendingRecovery {
      if appModel.pendingProofDraft != nil {
        return "Review the source, proposal, processing route, and locked destination."
      }
      return "Retry the original field, copy the result, or dismiss it intentionally."
    }
    if appModel.readiness.dictation.isBusy {
      return
        "\(busyActionTitle). Press Escape to cancel an active recording or wait for it to finish."
    }
    if appModel.readiness.dictation.isSetupReady {
      return
        "\(dictationInstruction). Effective route: \(appModel.dictationEffectiveRouteLabel)."
    }
    let count = appModel.readiness.dictation.setupBlockers.count
    let remaining = count == 1 ? "item remains" : "items remain"
    return
      "\(count) required setup \(remaining). "
      + "Each readiness row below includes its recovery action."
  }

  private var busyActionTitle: String {
    switch appModel.operationPhase {
    case .idle:
      "Starting…"
    case .recording, .transcribing, .awaitingLLM, .inserting, .failed:
      appModel.operationPhase.displayName
    }
  }

  private var dictationInstruction: String {
    let settings = appModel.settingsStore.settings
    switch settings.dictationActivationMode {
    case .hold:
      return "Hold \(settings.dictationHotkey.displayName), speak, then release"
    case .toggle:
      return "Press \(settings.dictationHotkey.displayName) to start and press it again to stop"
    }
  }
}

private struct MicAIWaveformMark: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14)
        .fill(
          LinearGradient(
            colors: [Color.accentColor, Color(nsColor: .systemTeal)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      Image(systemName: "waveform")
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(.white)
    }
    .frame(width: 68, height: 68)
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(.white.opacity(0.28), lineWidth: 1)
    }
    .shadow(color: Color.accentColor.opacity(0.22), radius: 10, y: 5)
    .accessibilityHidden(true)
  }
}

private struct LocalByDefaultCallout: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "lock.shield.fill")
        .font(.title2)
        .foregroundStyle(MicAIStatusColor.ready)
        .frame(width: 34, height: 34)
        .background(
          MicAIStatusColor.ready.opacity(0.12),
          in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text("Local by default")
          .font(.title3.weight(.semibold))
        Text(
          "With Parakeet, audio and ordinary dictation remain on this Mac. "
            + appModel.dictationPrivacyDetail
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      SettingsLink {
        Label("Review Route", systemImage: "gearshape")
      }
      .controlSize(.small)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(
        colors: [
          MicAIStatusColor.ready.opacity(0.11),
          Color(nsColor: .systemTeal).opacity(0.07),
        ],
        startPoint: .leading,
        endPoint: .trailing
      ),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(MicAIStatusColor.ready.opacity(0.20), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct SetupReadinessSection: View {
  @ObservedObject var appModel: AppModel
  let showDictation: () -> Void
  let showActivity: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Readiness")
            .font(.title2.weight(.semibold))
          Text("MicAI checks these locally and refreshes permission status when it becomes active.")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(readyItemCount) of 6 ready")
          .font(.callout.weight(.medium))
          .foregroundStyle(.secondary)
      }

      ProgressView(value: Double(readyItemCount), total: 6)
        .accessibilityLabel("MicAI setup readiness")
        .accessibilityValue("\(readyItemCount) of 6 items ready")

      VStack(spacing: 0) {
        microphoneRow
        Divider()
        accessibilityRow
        Divider()
        dictationProviderRow
        Divider()
        modelRow
        Divider()
        providerRow
        Divider()
        testRow
      }
    }
  }

  @ViewBuilder
  private var microphoneRow: some View {
    switch appModel.microphonePermission.status {
    case .granted:
      SetupReadinessRow(
        title: "Microphone",
        status: "Allowed",
        systemImage: "mic.fill",
        ready: true
      ) { EmptyView() }
    case .undetermined:
      SetupReadinessRow(
        title: "Microphone",
        status: "Permission not requested",
        systemImage: "mic.fill",
        ready: false
      ) {
        Button("Allow…") {
          appModel.requestMicrophonePermission()
        }
        .help("Request Microphone access from macOS")
      }
    case .denied:
      SetupReadinessRow(
        title: "Microphone",
        status: "Access denied",
        systemImage: "mic.fill",
        ready: false
      ) {
        Button("Open Settings…") {
          appModel.microphonePermission.openSystemSettings()
        }
        .help("Open the macOS Microphone privacy pane")
      }
    }
  }

  @ViewBuilder
  private var accessibilityRow: some View {
    if appModel.accessibilityPermission.isTrusted {
      SetupReadinessRow(
        title: "Accessibility",
        status: "Allowed",
        systemImage: "hand.raised.fill",
        ready: true
      ) { EmptyView() }
    } else {
      SetupReadinessRow(
        title: "Accessibility",
        status: "Required for hotkeys and insertion",
        systemImage: "hand.raised.fill",
        ready: false
      ) {
        Button("Review…") {
          appModel.showOnboarding()
        }
        .help("Review why MicAI needs Accessibility access")
      }
    }
  }

  @ViewBuilder
  private var dictationProviderRow: some View {
    SetupReadinessRow(
      title: "Dictation provider",
      status: appModel.dictationEffectiveRouteLabel,
      systemImage: appModel.settingsStore.settings.dictationProvider == .openAI
        ? "cloud.fill" : "waveform",
      ready: appModel.isDictationProviderReady
    ) {
      SettingsLink {
        Text("Review…")
      }
      .help("Review ordinary dictation provider and fallback settings")
    }
  }

  @ViewBuilder
  private var modelRow: some View {
    switch appModel.modelState {
    case .notDownloaded:
      SetupReadinessRow(
        title: "Local speech model",
        status: "Not prepared",
        systemImage: "waveform",
        ready: false
      ) {
        Button("Prepare") {
          appModel.prepareModel()
        }
        .help("Download and prepare the local Parakeet model")
      }
    case .preparing(let fraction, let phase):
      SetupReadinessRow(
        title: "Local speech model",
        status: phase,
        systemImage: "waveform",
        ready: false
      ) {
        ProgressView(value: fraction)
          .frame(width: 90)
          .accessibilityLabel("Local speech model preparation")
          .accessibilityValue("\(Int(fraction * 100)) percent")
      }
    case .ready:
      SetupReadinessRow(
        title: "Local speech model",
        status: "Parakeet is ready on this Mac",
        systemImage: "waveform",
        ready: true
      ) { EmptyView() }
    case .failed:
      SetupReadinessRow(
        title: "Local speech model",
        status: "Preparation failed",
        systemImage: "waveform",
        ready: false
      ) {
        Button("Retry") {
          appModel.prepareModel()
        }
        .help("Retry local speech model preparation")
      }
    }
  }

  @ViewBuilder
  private var providerRow: some View {
    if providerConfigured {
      SetupReadinessRow(
        title: "AI Commands",
        status: "Configured; ChatGPT is checked only when used",
        systemImage: "sparkles",
        ready: true
      ) { EmptyView() }
    } else {
      SetupReadinessRow(
        title: "AI Commands",
        status: "Hotkey or ChatGPT model not configured",
        systemImage: "sparkles",
        ready: false
      ) {
        SettingsLink {
          Text("Configure…")
        }
      }
    }
  }

  private var testRow: some View {
    SetupReadinessRow(
      title: "Quick test",
      status: quickTestStatus,
      systemImage: "checkmark.bubble.fill",
      ready: appModel.readiness.dictation.isSetupReady
    ) {
      if appModel.readiness.dictation.hasPendingRecovery {
        Button("Resolve Result", action: showActivity)
      } else if appModel.readiness.dictation.isBusy {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text("Busy")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick test unavailable while MicAI is busy")
      } else if appModel.readiness.dictation.isSetupReady {
        Button("How to Test", action: showDictation)
      } else {
        Button("Review Setup") {
          appModel.showOnboarding()
        }
      }
    }
  }

  private var providerConfigured: Bool {
    let settings = appModel.settingsStore.settings
    return settings.commandHotkey != nil
      && !settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var readyItemCount: Int {
    [
      appModel.microphonePermission.isGranted,
      appModel.accessibilityPermission.isTrusted,
      appModel.isDictationProviderReady,
      appModel.modelState == .ready,
      providerConfigured,
      appModel.readiness.dictation.isSetupReady,
    ].filter { $0 }.count
  }

  private var quickTestStatus: String {
    if appModel.readiness.dictation.hasPendingRecovery {
      return "Resolve the saved result before another test"
    }
    if appModel.readiness.dictation.isBusy {
      return appModel.readiness.dictation.isSetupReady
        ? "Setup ready; current operation in progress"
        : "Current operation in progress"
    }
    return appModel.readiness.dictation.isSetupReady
      ? "Ready to try in any text field" : "Available after required setup"
  }
}

private struct SetupReadinessRow<Action: View>: View {
  let title: String
  let status: String
  let systemImage: String
  let ready: Bool
  private let action: Action

  init(
    title: String,
    status: String,
    systemImage: String,
    ready: Bool,
    @ViewBuilder action: () -> Action
  ) {
    self.title = title
    self.status = status
    self.systemImage = systemImage
    self.ready = ready
    self.action = action()
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.body.weight(.medium))
        Label {
          Text(status)
        } icon: {
          Image(
            systemName: ready
              ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
          )
          .foregroundStyle(ready ? MicAIStatusColor.ready : MicAIStatusColor.attention)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(status)")
      }

      Spacer(minLength: 16)
      action
        .controlSize(.small)
    }
    .padding(.vertical, 11)
    .frame(minHeight: 58)
  }
}

private struct HomeWorkflowSection: View {
  @ObservedObject var appModel: AppModel
  let showSection: (PrimarySection) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeading(
        title: "Core workflows",
        subtitle: "Two shortcuts, two clear privacy boundaries, available from any app."
      )

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) {
          workflowCards
        }

        VStack(spacing: 16) {
          workflowCards
        }
      }
    }
  }

  @ViewBuilder
  private var workflowCards: some View {
    HomeWorkflowCard(
      title: "Dictation",
      subtitle: "Type with your voice",
      systemImage: "mic.fill",
      tint: Color(nsColor: .systemBlue),
      shortcut: appModel.settingsStore.settings.dictationHotkey.displayName,
      route: appModel.dictationEffectiveRouteLabel,
      detail:
        "Hold or toggle the shortcut, speak naturally, and MicAI returns polished text "
        + "to the original cursor.",
      readiness: appModel.readiness.dictation,
      actionTitle: "Open Dictation"
    ) {
      showSection(.dictation)
    }

    HomeWorkflowCard(
      title: "AI Commands",
      subtitle: "Transform text on demand",
      systemImage: "sparkles",
      tint: Color(nsColor: .systemPurple),
      shortcut: appModel.settingsStore.settings.commandHotkey?.displayName
        ?? "Not configured",
      route: "Explicit ChatGPT request",
      detail:
        "Select text and speak an instruction to rewrite it, or draft new text "
        + "at the cursor.",
      readiness: appModel.readiness.command,
      actionTitle: "Open AI Commands"
    ) {
      showSection(.commands)
    }
  }
}

private struct HomeWorkflowCard: View {
  @Environment(\.colorScheme) private var colorScheme

  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color
  let shortcut: String
  let route: String
  let detail: String
  let readiness: FeatureReadiness
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 46, height: 46)
          .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(tint.opacity(0.16), lineWidth: 1)
          }
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.title2.weight(.semibold))
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)
      }

      Text(route)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Text(detail)
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)

      HStack(alignment: .center, spacing: 12) {
        Text(shortcut)
          .font(.system(.callout, design: .rounded).weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(
            Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06),
            in: RoundedRectangle(cornerRadius: 7)
          )
          .accessibilityLabel("Shortcut: \(shortcut)")

        Spacer(minLength: 8)

        Label(statusTitle, systemImage: statusImage)
          .font(.callout.weight(.medium))
          .foregroundStyle(statusColor)
          .lineLimit(1)
      }

      Button(actionTitle, action: action)
        .controlSize(.small)
        .micAISecondaryButtonStyle()
        .accessibilityHint("Shows \(title.lowercased()) instructions and readiness.")
    }
    .padding(20)
    .frame(minWidth: 270, maxWidth: .infinity, minHeight: 238, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(
          Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.62 : 0.86)
        )
    }
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(tint.opacity(colorScheme == .dark ? 0.26 : 0.18), lineWidth: 1)
    }
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.10 : 0.045), radius: 9, y: 4)
    .accessibilityElement(children: .contain)
  }

  private var statusTitle: String {
    if readiness.hasPendingRecovery {
      return "Saved result"
    }
    if readiness.isBusy {
      return "In progress"
    }
    if readiness.isSetupReady {
      return "Ready"
    }
    let count = readiness.setupBlockers.count
    return count == 1 ? "1 setup item" : "\(count) setup items"
  }

  private var statusImage: String {
    if readiness.hasPendingRecovery {
      return "doc.badge.clock"
    }
    if readiness.isBusy {
      return "hourglass.circle.fill"
    }
    return readiness.isSetupReady
      ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
  }

  private var statusColor: Color {
    if readiness.hasPendingRecovery {
      return MicAIStatusColor.attention
    }
    if readiness.isBusy {
      return tint
    }
    return readiness.isSetupReady
      ? MicAIStatusColor.ready : MicAIStatusColor.attention
  }
}

private struct HomeProofCallout: View {
  let draft: ProofCarryingDraft
  let review: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "checkmark.shield.fill")
        .font(.title2)
        .foregroundStyle(MicAIStatusColor.attention)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text("Transformation withheld for approval")
          .font(.headline)
        Text(draft.proposedText)
          .lineLimit(3)
          .foregroundStyle(.secondary)
        Text("Target: \(draft.targetLabel) · Local + network receipt attached")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      Button("Review Proof", action: review)
        .micAIPrimaryButtonStyle()
    }
    .padding(14)
    .background(
      MicAIStatusColor.attention.opacity(0.10),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .accessibilityElement(children: .contain)
  }
}

private struct HomePrivacySection: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(
        title: "Privacy and providers",
        subtitle: "Ordinary dictation and optional AI Commands use separate paths."
      )

      HomeInfoRow(
        title: "Ordinary dictation",
        value: appModel.dictationSelectedRouteLabel,
        detail: appModel.dictationPrivacyDetail,
        systemImage: appModel.settingsStore.settings.dictationProvider == .openAI
          ? "cloud.fill" : "lock.shield.fill"
      )

      Divider()

      HomeInfoRow(
        title: "Local speech model",
        value: "Parakeet TDT v2",
        detail:
          "AI Command speech always stays on this Mac. Parakeet also provides "
          + "the optional offline fallback for ordinary dictation.",
        systemImage: "lock.shield.fill"
      )

      Divider()

      HomeInfoRow(
        title: "AI Commands",
        value: "Experimental personal route",
        detail:
          "Only an explicit spoken command and the selected text are sent "
          + "through the local Codex sign-in. This is not a supported public "
          + "OpenAI API authentication method.",
        systemImage: "sparkles"
      )

      Divider()

      HomeInfoRow(
        title: "Menu bar and window",
        value: "Always available",
        detail:
          "MicAI stays in the menu bar without a Dock icon. Open this window "
          + "for setup, status, shortcuts, and session activity.",
        systemImage: "menubar.rectangle"
      )

      SettingsLink {
        Label("Review Provider Settings", systemImage: "gearshape")
      }
      .controlSize(.small)
    }
  }
}

private struct HomeInfoRow: View {
  let title: String
  let value: String
  let detail: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(title)
            .font(.body.weight(.medium))
          Spacer()
          Text(value)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
        }
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title), \(value). \(detail)")
  }
}

private struct HomeActivitySection: View {
  @ObservedObject var appModel: AppModel
  let showSection: (PrimarySection) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(
        title: "Recent activity",
        subtitle: "Only the most recent result from this running session appears here."
      )

      if let draft = appModel.pendingProofDraft {
        VStack(alignment: .leading, spacing: 8) {
          Label("Proof draft awaiting approval", systemImage: "checkmark.shield")
            .font(.body.weight(.medium))
            .foregroundStyle(MicAIStatusColor.attention)
          Text(draft.proposedText)
            .lineLimit(4)
            .textSelection(.enabled)
          Button("Review Proof") {
            showSection(.proof)
          }
          .controlSize(.small)
        }
      } else if let recovery = appModel.recoverableInsertion {
        VStack(alignment: .leading, spacing: 8) {
          Label("Saved result needs attention", systemImage: "doc.badge.clock")
            .font(.body.weight(.medium))
            .foregroundStyle(MicAIStatusColor.attention)
          Text(recovery.text)
            .lineLimit(4)
            .textSelection(.enabled)
          Button("Resolve in Activity") {
            showSection(.activity)
          }
          .controlSize(.small)
        }
      } else if let transcript = appModel.lastTranscript, !transcript.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Label("Most recent result", systemImage: "text.bubble.fill")
            .font(.body.weight(.medium))
          Text(transcript)
            .lineLimit(4)
            .textSelection(.enabled)
          Button("Open Activity") {
            showSection(.activity)
          }
          .controlSize(.small)
        }
      } else {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "clock")
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text("No activity this session")
              .font(.body.weight(.medium))
            Text(
              "MicAI does not keep a transcription history. "
                + "A completed result appears here until the app quits."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}

private struct HomeErrorBanner: View {
  let message: String
  let reviewSetup: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(MicAIStatusColor.attention)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text("MicAI needs attention")
          .font(.body.weight(.semibold))
        Text(message)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      Spacer()
      Button("Review Setup", action: reviewSetup)
        .controlSize(.small)
    }
    .padding(14)
    .background(MicAIStatusColor.attention.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .contain)
  }
}

private struct SectionHeading: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.title2.weight(.semibold))
      Text(subtitle)
        .foregroundStyle(.secondary)
    }
  }
}
