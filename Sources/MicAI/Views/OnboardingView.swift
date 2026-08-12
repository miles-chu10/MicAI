import MicAICore
import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Identifiable {
  case welcome
  case microphone
  case accessibility
  case speechModel
  case commands

  var id: Self { self }

  var shortTitle: String {
    switch self {
    case .welcome:
      "Overview"
    case .microphone:
      "Microphone"
    case .accessibility:
      "Accessibility"
    case .speechModel:
      "Transcription"
    case .commands:
      "AI Commands"
    }
  }

  var systemImage: String {
    switch self {
    case .welcome:
      "mic.and.signal.meter.fill"
    case .microphone:
      "mic.fill"
    case .accessibility:
      "hand.raised.fill"
    case .speechModel:
      "waveform"
    case .commands:
      "sparkles"
    }
  }

  var title: String {
    switch self {
    case .welcome:
      "Welcome to MicAI"
    case .microphone:
      "Allow your microphone"
    case .accessibility:
      "Enable cross-app insertion"
    case .speechModel:
      "Choose how dictation is transcribed"
    case .commands:
      "Configure AI Commands"
    }
  }
}

struct OnboardingView: View {
  @ObservedObject var appModel: AppModel
  @State private var step: OnboardingStep = .welcome
  @FocusState private var primaryActionFocused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        Text("MicAI Setup")
          .font(.headline)
          .padding(.horizontal, 12)
          .padding(.top, 16)

        List(OnboardingStep.allCases, selection: $step) { item in
          OnboardingStepRow(
            step: item,
            status: status(for: item)
          )
          .tag(item)
        }
        .listStyle(.sidebar)

        Label(
          "Clear provider boundaries",
          systemImage: "point.3.connected.trianglepath.dotted"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
      }
      .frame(width: 210)
      .background(.bar)

      Divider()

      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
              .font(.callout)
              .foregroundStyle(.secondary)
            Spacer()
            OnboardingStatusLabel(status: status(for: step))
          }
          ProgressView(
            value: Double(step.rawValue + 1),
            total: Double(OnboardingStep.allCases.count)
          )
          .accessibilityLabel("Setup progress")
          .accessibilityValue(
            "Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)"
          )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)

        Divider()

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text(step.title)
              .font(.title.bold())
            stepContent
          }
          .padding(.horizontal, 32)
          .padding(.vertical, 26)
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        Divider()
        MicAIActionCluster {
          HStack {
            Group {
              if step == .welcome {
                Button("Back", systemImage: "chevron.left") {}
                  .hidden()
              } else {
                Button("Back", systemImage: "chevron.left") {
                  move(by: -1)
                }
              }
            }
            .micAISecondaryButtonStyle()

            Spacer()

            Button(
              step == .commands ? "Finish for Now" : "Continue",
              systemImage: step == .commands ? "checkmark" : "chevron.right"
            ) {
              if step == .commands {
                appModel.dismissOnboarding()
                dismiss()
              } else {
                move(by: 1)
              }
            }
            .micAIPrimaryButtonStyle()
            .keyboardShortcut(.defaultAction)
            .focused($primaryActionFocused)
          }
        }
        .padding(18)
        .background(.bar)
      }
    }
    .frame(width: 760, height: 560)
    .interactiveDismissDisabled()
    .onAppear {
      primaryActionFocused = true
    }
    .onChange(of: step) { _, _ in
      primaryActionFocused = true
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .welcome:
      IntroStep()
    case .microphone:
      microphoneStep
    case .accessibility:
      accessibilityStep
    case .speechModel:
      speechModelStep
    case .commands:
      commandStep
    }
  }

  private var microphoneStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "MicAI records only while you invoke a dictation or command hotkey. Ordinary dictation uses your selected provider; AI Command speech stays on this Mac."
      )
      StatusLine(
        title: microphoneStatus,
        ready: appModel.microphonePermission.isGranted
      )
      HStack {
        if appModel.microphonePermission.status == .undetermined {
          Button("Request Microphone Access") {
            appModel.requestMicrophonePermission()
          }
          .buttonStyle(.borderedProminent)
        } else if !appModel.microphonePermission.isGranted {
          Button("Open Microphone Settings") {
            appModel.microphonePermission.openSystemSettings()
          }
        }
      }
    }
  }

  private var accessibilityStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "Accessibility lets MicAI monitor the global hotkeys and synthesize Command-C and Command-V. It is required to preserve your clipboard and insert into the original app."
      )
      StatusLine(
        title: appModel.accessibilityPermission.isTrusted
          ? "Accessibility is allowed" : "Accessibility is not allowed yet",
        ready: appModel.accessibilityPermission.isTrusted
      )
      HStack {
        Button("Request Accessibility Access") {
          appModel.requestAccessibilityPermission()
        }
        .buttonStyle(.borderedProminent)
        Button("Open Accessibility Settings") {
          appModel.accessibilityPermission.openSystemSettings()
        }
        Button("Check Again") {
          appModel.refreshSystemStatus()
        }
      }
      Text(
        "macOS grants this in System Settings → Privacy & Security → Accessibility. The status may not update until you return to MicAI."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var speechModelStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "Choose OpenAI gpt-transcribe for completed recordings or Parakeet for fully on-device transcription. OpenAI API access is not configured yet, so MicAI never sends audio in this build."
      )
      LabeledContent(
        "Selected provider",
        value: appModel.dictationSelectedRouteLabel
      )
      LabeledContent("Effective route") {
        Text(appModel.dictationEffectiveRouteLabel)
          .multilineTextAlignment(.trailing)
      }
      Label(
        appModel.dictationProviderStatus.summary,
        systemImage: appModel.isDictationProviderReady
          ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
      )
      .foregroundStyle(
        appModel.isDictationProviderReady ? MicAIStatusColor.ready : MicAIStatusColor.attention)

      if appModel.settingsStore.settings.dictationProvider == .parakeet
        || appModel.settingsStore.settings.openAITranscriptionFallbackEnabled
      {
        ModelStatusView(
          state: appModel.modelState,
          transcript: nil,
          prepare: appModel.prepareModel
        )
      }

      SettingsLink {
        Label("Review Transcription Settings", systemImage: "gearshape")
      }
      Text(
        "Preparing Parakeet may download and compile model files. MicAI never starts that download automatically."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var commandStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "AI Commands are a personal-use preview that reads your existing Codex CLI sign-in at command time. MicAI never displays, copies, or stores its values."
      )
      LabeledContent(
        "Command hotkey",
        value: appModel.settingsStore.settings.commandHotkey?.displayName
          ?? "Choose one in Settings"
      )
      LabeledContent(
        "ChatGPT model",
        value: appModel.settingsStore.settings.llmModel.isEmpty
          ? "Choose one in Settings" : appModel.settingsStore.settings.llmModel
      )
      Text(appModel.providerStatus.summary)
        .foregroundStyle(.secondary)
      Text(
        "This personal prototype route is experimental and is not a supported public OpenAI API authentication method."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Text(
        "You can finish setup with a blocker. MicAI will continue to show exactly what Dictation or AI Commands still need."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var microphoneStatus: String {
    switch appModel.microphonePermission.status {
    case .undetermined:
      "Microphone access has not been requested"
    case .denied:
      "Microphone access is denied"
    case .granted:
      "Microphone access is allowed"
    }
  }

  private func status(for item: OnboardingStep) -> OnboardingStepStatus {
    switch item {
    case .welcome:
      return OnboardingStepStatus(
        title: "Overview",
        systemImage: "info.circle.fill",
        tint: .secondary
      )
    case .microphone:
      return OnboardingStepStatus(
        title: appModel.microphonePermission.isGranted ? "Ready" : "Action needed",
        systemImage: appModel.microphonePermission.isGranted
          ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
        tint: appModel.microphonePermission.isGranted
          ? MicAIStatusColor.ready : MicAIStatusColor.attention
      )
    case .accessibility:
      return OnboardingStepStatus(
        title: appModel.accessibilityPermission.isTrusted ? "Ready" : "Action needed",
        systemImage: appModel.accessibilityPermission.isTrusted
          ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
        tint: appModel.accessibilityPermission.isTrusted
          ? MicAIStatusColor.ready : MicAIStatusColor.attention
      )
    case .speechModel:
      if case .preparing = appModel.modelState {
        return OnboardingStepStatus(
          title: "Preparing",
          systemImage: "arrow.down.circle.fill",
          tint: .accentColor
        )
      }
      if appModel.isDictationProviderReady {
        return OnboardingStepStatus(
          title: "Ready",
          systemImage: "checkmark.circle.fill",
          tint: MicAIStatusColor.ready
        )
      }
      return OnboardingStepStatus(
        title: "Action needed",
        systemImage: "exclamationmark.circle.fill",
        tint: MicAIStatusColor.attention
      )
    case .commands:
      let settings = appModel.settingsStore.settings
      let configured =
        settings.commandHotkey != nil
        && !settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      return OnboardingStepStatus(
        title: configured ? "Configured" : "Optional",
        systemImage: configured ? "checkmark.circle.fill" : "circle.dashed",
        tint: configured ? MicAIStatusColor.ready : .secondary
      )
    }
  }

  private func move(by offset: Int) {
    guard
      let next = OnboardingStep(rawValue: step.rawValue + offset)
    else {
      return
    }
    step = next
  }
}

private struct OnboardingStepStatus {
  let title: String
  let systemImage: String
  let tint: Color
}

private struct OnboardingStepRow: View {
  let step: OnboardingStep
  let status: OnboardingStepStatus

  var body: some View {
    HStack(spacing: 8) {
      Label(step.shortTitle, systemImage: step.systemImage)
      Spacer(minLength: 4)
      Image(systemName: status.systemImage)
        .foregroundStyle(status.tint)
        .help(status.title)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(step.shortTitle): \(status.title)")
  }
}

private struct OnboardingStatusLabel: View {
  let status: OnboardingStepStatus

  var body: some View {
    Label(status.title, systemImage: status.systemImage)
      .font(.callout)
      .foregroundStyle(.secondary)
      .symbolRenderingMode(.hierarchical)
      .accessibilityLabel("Current step status: \(status.title)")
  }
}

private struct IntroStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "mic.and.signal.meter.fill")
        .font(.largeTitle)
        .foregroundStyle(.tint)
        .padding(16)
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityHidden(true)
      Label(
        "Choose on-device or OpenAI dictation",
        systemImage: "mic.and.signal.meter.fill"
      )
      Label(
        "Transform selected text with a spoken command",
        systemImage: "sparkles"
      )
      Label(
        "Cancel safely with Escape before insertion",
        systemImage: "escape"
      )
      Text(
        "Setup covers Microphone, Accessibility, transcription routing, the optional local model, and AI Commands."
      )
      .foregroundStyle(.secondary)
    }
    .font(.title3)
  }
}

private struct StatusLine: View {
  let title: String
  let ready: Bool

  var body: some View {
    Label {
      Text(title)
    } icon: {
      Image(
        systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
      )
      .foregroundStyle(ready ? MicAIStatusColor.ready : MicAIStatusColor.attention)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(ready ? "Ready" : "Needs attention")")
  }
}
