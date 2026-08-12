import MicAICore
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
  case welcome
  case microphone
  case accessibility
  case speechModel
  case commands

  var title: String {
    switch self {
    case .welcome:
      "Welcome to MicAI"
    case .microphone:
      "Allow your microphone"
    case .accessibility:
      "Enable cross-app insertion"
    case .speechModel:
      "Prepare local transcription"
    case .commands:
      "Configure AI Commands"
    }
  }
}

struct OnboardingView: View {
  @ObservedObject var appModel: AppModel
  @State private var step: OnboardingStep = .welcome
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
          Capsule()
            .fill(
              item.rawValue <= step.rawValue
                ? Color.accentColor : Color.secondary.opacity(0.18)
            )
            .frame(height: 5)
        }
      }
      .padding(24)

      VStack(alignment: .leading, spacing: 20) {
        Text(step.title)
          .font(.largeTitle.weight(.semibold))
        stepContent
        Spacer()
      }
      .padding(.horizontal, 36)
      .padding(.bottom, 28)

      Divider()
      HStack {
        if step != .welcome {
          Button("Back") {
            move(by: -1)
          }
        }
        Spacer()
        Button(step == .commands ? "Finish for Now" : "Continue") {
          if step == .commands {
            appModel.dismissOnboarding()
            dismiss()
          } else {
            move(by: 1)
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
      .padding(20)
    }
    .frame(width: 620, height: 500)
    .interactiveDismissDisabled()
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
        "MicAI records only while you invoke a dictation or command hotkey. Ordinary dictation audio never leaves this Mac."
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
        "MicAI uses the Parakeet TDT 0.6b v2 Core ML model. Preparing it can download and compile model files, then all ordinary transcription runs locally."
      )
      ModelStatusView(
        state: appModel.modelState,
        transcript: nil,
        prepare: appModel.prepareModel
      )
    }
  }

  private var commandStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "AI Commands send only your spoken instruction and selected text to the configured OpenAI model. The default provider uses an OPENAI_API_KEY environment variable, which is never displayed or stored; a ChatGPT-subscription provider that reuses your Codex CLI sign-in is available in Settings."
      )
      LabeledContent(
        "Command hotkey",
        value: appModel.settingsStore.settings.commandHotkey?.displayName
          ?? "Choose one in Settings"
      )
      LabeledContent(
        appModel.settingsStore.settings.llmProvider.modelFieldLabel,
        value: appModel.settingsStore.settings.llmModel.isEmpty
          ? "Choose one in Settings" : appModel.settingsStore.settings.llmModel
      )
      Text(
        appModel.providerStatus.summary(
          for: appModel.settingsStore.settings.llmProvider
        )
      )
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

  private func move(by offset: Int) {
    guard
      let next = OnboardingStep(rawValue: step.rawValue + offset)
    else {
      return
    }
    step = next
  }
}

private struct IntroStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label(
        "Dictate locally in any app",
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
        "Setup covers Microphone, Accessibility, the local speech model, and optional AI commands."
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
    Label(
      title,
      systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle"
    )
    .foregroundStyle(ready ? Color.green : Color.orange)
  }
}
