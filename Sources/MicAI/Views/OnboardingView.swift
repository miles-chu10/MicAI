import MicAICore
import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Identifiable {
  case welcome
  case microphone
  case accessibility
  case speechModel
  case tryIt

  var id: Self { self }

  var title: String {
    switch self {
    case .welcome:
      "Welcome"
    case .microphone:
      "Microphone"
    case .accessibility:
      "Accessibility"
    case .speechModel:
      "Speech model"
    case .tryIt:
      "Try your shortcut"
    }
  }
}

/// First run: one requirement per step, the step list on the left so you can
/// see how far there is to go, and a single obvious action on each step.
struct OnboardingView: View {
  @ObservedObject var appModel: AppModel
  @State private var step: OnboardingStep = .welcome
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    HStack(spacing: 0) {
      stepList
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            content
          }
          .padding(36)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        Divider()
        footer
      }
    }
    .frame(width: 740, height: 500)
    .interactiveDismissDisabled()
  }

  private var stepList: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Set up MicAI")
          .font(.headline)
        Text("About a minute")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)

      VStack(alignment: .leading, spacing: 2) {
        ForEach(OnboardingStep.allCases) { item in
          Button {
            step = item
          } label: {
            HStack(spacing: 10) {
              badge(for: item)
              Text(item.title)
                .foregroundStyle(item == step ? .primary : .secondary)
              Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
              item == step
                ? AnyShapeStyle(HierarchicalShapeStyle.quaternary) : AnyShapeStyle(Color.clear),
              in: .rect(cornerRadius: 7)
            )
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(item == step ? .isSelected : [])
        }
      }
      Spacer()
    }
    .padding(16)
    .frame(width: 220)
    .background(.background.secondary)
  }

  @ViewBuilder
  private func badge(for item: OnboardingStep) -> some View {
    if isDone(item) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .frame(width: 20)
    } else {
      Text("\(item.rawValue + 1)")
        .font(.caption.weight(.semibold))
        .frame(width: 20, height: 20)
        .overlay {
          Circle().strokeBorder(item == step ? Color.primary : Color.secondary.opacity(0.4))
        }
    }
  }

  private func isDone(_ item: OnboardingStep) -> Bool {
    switch item {
    case .welcome:
      step.rawValue > item.rawValue
    case .microphone:
      appModel.microphonePermission.isGranted
    case .accessibility:
      appModel.accessibilityPermission.isTrusted
    case .speechModel:
      appModel.modelState == .ready
    case .tryIt:
      appModel.lastResult != nil
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .welcome:
      header("mic.fill", "Speak anywhere you type")
      Text(
        "Hold a key, talk, and polished text appears at your cursor, in any app. Speech is "
          + "recognised on this Mac."
      )
      .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 12) {
        ForEach(MicAIMode.allCases, id: \.self) { mode in
          HStack(spacing: 10) {
            Image(systemName: mode.symbol)
              .foregroundStyle(mode.tint)
              .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
              Text(mode.shortName).fontWeight(.medium)
              Text(mode.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    case .microphone:
      header("mic.circle", "Let MicAI hear you")
      Text(
        "MicAI records only while you hold one of its shortcuts. Audio is transcribed on this Mac "
          + "and never uploaded."
      )
      .foregroundStyle(.secondary)
      status("Microphone", ready: appModel.microphonePermission.isGranted)
      HStack {
        if appModel.microphonePermission.status == .undetermined {
          Button("Allow Microphone") {
            appModel.requestMicrophonePermission()
          }
          .buttonStyle(.borderedProminent)
        } else if !appModel.microphonePermission.isGranted {
          Button("Open Microphone Settings") {
            appModel.microphonePermission.openSystemSettings()
          }
          .buttonStyle(.borderedProminent)
        }
      }
    case .accessibility:
      header("keyboard", "Let MicAI type where you’re typing")
      Text(
        "MicAI pastes your words at the cursor, then puts your clipboard back the way it was. "
          + "macOS asks you to allow Accessibility for that, and for the shortcuts to work in "
          + "every app."
      )
      .foregroundStyle(.secondary)
      status("Accessibility", ready: appModel.accessibilityPermission.isTrusted)
      if !appModel.accessibilityPermission.isTrusted {
        HStack {
          Button("Open Accessibility Settings") {
            appModel.requestAccessibilityPermission()
            appModel.accessibilityPermission.openSystemSettings()
          }
          .buttonStyle(.borderedProminent)
          Button("Check Again") {
            appModel.refreshSystemStatus()
          }
        }
        Text(
          "Find MicAI in the list and switch it on. You may need to quit and reopen MicAI "
            + "afterwards."
        )
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .speechModel:
      header("laptopcomputer", "Download the speech model")
      Text(
        "Downloaded once. After that, recognition works offline and nothing you say leaves this "
          + "Mac."
      )
      .foregroundStyle(.secondary)
      Picker("Language", selection: speechModelBinding) {
        ForEach(SpeechModelChoice.allCases, id: \.self) { choice in
          Text("\(choice.displayName) — \(choice.detail)").tag(choice)
        }
      }
      .pickerStyle(.radioGroup)
      ModelStatusView(state: appModel.modelState, prepare: appModel.prepareModel)
    case .tryIt:
      header("hand.tap", "Try it")
      Text(tryItInstruction)
        .foregroundStyle(.secondary)
      KeyCaps(appModel.settingsStore.settings.dictationHotkey)
      if let lastResult = appModel.lastResult {
        GroupBox("You dictated") {
          Text(lastResult)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Text(
        "Clean-up, Command, Translate and Ask AI need a language model. Choose one in Settings "
          + "whenever you like."
      )
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var footer: some View {
    HStack {
      if step != .welcome {
        Button("Back") {
          move(by: -1)
        }
      }
      Spacer()
      Button(step == .tryIt ? "Done" : "Continue") {
        if step == .tryIt {
          appModel.dismissOnboarding()
          dismiss()
        } else {
          move(by: 1)
        }
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
    }
    .padding(16)
  }

  private func header(_ symbol: String, _ title: String) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: 52, height: 52)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityHidden(true)
      Text(title)
        .font(.title.weight(.semibold))
    }
  }

  private func status(_ title: String, ready: Bool) -> some View {
    GroupBox {
      LabeledContent(title) {
        Label(
          ready ? "Allowed" : "Not allowed yet",
          systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .foregroundStyle(ready ? Color.green : Color.orange)
      }
      .padding(4)
    }
  }

  /// Saves immediately: this is the only setting on the step, and the model
  /// choice must be in effect before the download button is pressed.
  private var speechModelBinding: Binding<SpeechModelChoice> {
    Binding(
      get: { appModel.settingsStore.settings.speechModel },
      set: { choice in
        var settings = appModel.settingsStore.settings
        settings.speechModel = choice
        if appModel.settingsStore.save(settings) {
          appModel.applySettings()
        }
      }
    )
  }

  private var tryItInstruction: String {
    let settings = appModel.settingsStore.settings
    let key = settings.dictationHotkey.displayName
    switch settings.dictationActivationMode {
    case .hold, .hybrid:
      return "Click into any text field, hold \(key), say a sentence, and let go."
    case .toggle:
      return "Click into any text field, press \(key), say a sentence, and press it again."
    }
  }

  private func move(by offset: Int) {
    guard let next = OnboardingStep(rawValue: step.rawValue + offset) else {
      return
    }
    step = next
  }
}
