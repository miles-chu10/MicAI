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
      MicAIActionCluster {
        HStack {
          if step != .welcome {
            Button("Back", systemImage: "chevron.left") {
              move(by: -1)
            }
            .micAISecondaryButtonStyle()
          }
          Spacer()
          Button(step == .commands ? "Finish" : "Continue") {
            if step == .commands {
              appModel.dismissOnboarding()
              dismiss()
            } else {
              move(by: 1)
            }
          }
          .micAIPrimaryButtonStyle()
          .keyboardShortcut(.defaultAction)
        }
      }
      .padding(20)
    }
    .frame(width: 620, height: 560)
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
          .micAIPrimaryButtonStyle()
        } else if !appModel.microphonePermission.isGranted {
          Button("Open Microphone Settings") {
            appModel.microphonePermission.openSystemSettings()
          }
          .micAISecondaryButtonStyle()
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
        .micAIPrimaryButtonStyle()
        Button("Open Accessibility Settings") {
          appModel.accessibilityPermission.openSystemSettings()
        }
        .micAISecondaryButtonStyle()
        Button("Check Again") {
          appModel.refreshSystemStatus()
        }
        .micAISecondaryButtonStyle()
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
        "AI Commands run through your signed-in Codex CLI using your ChatGPT subscription. MicAI never reads, displays, or stores OAuth token values."
      )
      HotkeyRecorderField(title: "Command hotkey", hotkey: commandHotkey)
      PermissionStatusView(appModel: appModel)
      Text(
        "You can finish setup with a blocker. MicAI keeps showing exactly what Dictation or AI Commands still need."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  /// Saved immediately, like the permission buttons on the other steps, so
  /// setup never ends with an unsaved choice.
  private var commandHotkey: Binding<Hotkey?> {
    Binding(
      get: { appModel.settingsStore.settings.commandHotkey },
      set: { hotkey in
        var settings = appModel.settingsStore.settings
        settings.commandHotkey = hotkey
        if appModel.settingsStore.save(settings) {
          appModel.applySettings()
        }
      }
    )
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
    Label(
      title,
      systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle"
    )
    .foregroundStyle(ready ? MicAIStatusColor.ready : MicAIStatusColor.attention)
  }
}
