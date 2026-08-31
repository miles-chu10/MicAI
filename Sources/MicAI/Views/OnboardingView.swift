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
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Text("MicAI setup")
            .font(.callout)
            .foregroundStyle(.secondary)
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
      .padding(.horizontal, 32)
      .padding(.vertical, 20)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(step.title)
            .font(.title.bold())
          stepContent
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Divider()
      HStack {
        if step != .welcome {
          Button("Back", systemImage: "chevron.left") {
            move(by: -1)
          }
        }
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
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
      .padding(20)
    }
    .frame(width: 640, height: 540)
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
        "AI Commands use your existing Codex sign-in with ChatGPT for subscription access. MicAI treats that credential as read-only and never displays or stores its values."
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
      Image(systemName: "mic.and.signal.meter.fill")
        .font(.largeTitle)
        .foregroundStyle(.tint)
        .padding(16)
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityHidden(true)
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
        "Setup covers Microphone, Accessibility, the local speech model, and optional ChatGPT commands."
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
      .foregroundStyle(ready ? Color.green : Color.orange)
    }
  }
}
