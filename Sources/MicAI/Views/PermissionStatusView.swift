import MicAICore
import SwiftUI

/// Microphone, Accessibility, speech model and AI provider as four separate
/// rows, each with its own fix, so "not ready" always says which part.
struct PermissionStatusView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.element.title) { index, row in
        if index > 0 {
          Divider().padding(.leading, 44)
        }
        StatusRowView(row: row)
      }
    }
    .micAICardSurface()
  }

  private var rows: [StatusRow] {
    [microphone, accessibility, speechModel, provider]
  }

  private var microphone: StatusRow {
    let permission = appModel.microphonePermission
    if permission.isGranted {
      return StatusRow(title: "Microphone", icon: "mic.fill", state: .ready, detail: "Allowed")
    }
    let undetermined = permission.status == .undetermined
    return StatusRow(
      title: "Microphone",
      icon: "mic.fill",
      state: .blocked,
      detail: undetermined ? "Not requested yet" : "Denied in System Settings",
      actionTitle: undetermined ? "Allow…" : "Open Settings…",
      action: undetermined
        ? appModel.requestMicrophonePermission
        : permission.openSystemSettings
    )
  }

  private var accessibility: StatusRow {
    if appModel.accessibilityPermission.isTrusted {
      return StatusRow(
        title: "Accessibility",
        icon: "accessibility",
        state: .ready,
        detail: "Allowed — MicAI can insert text"
      )
    }
    return StatusRow(
      title: "Accessibility",
      icon: "accessibility",
      state: .blocked,
      detail: "Needed to insert text and read selections",
      actionTitle: "Allow…",
      action: appModel.requestAccessibilityPermission
    )
  }

  private var speechModel: StatusRow {
    switch appModel.modelState {
    case .ready:
      return StatusRow(
        title: "Speech model",
        icon: "waveform",
        state: .ready,
        detail: "Parakeet ready on this Mac"
      )
    case .preparing(let fraction, let phase):
      return StatusRow(
        title: "Speech model",
        icon: "waveform",
        state: .working(fraction),
        detail: phase
      )
    case .notDownloaded:
      return StatusRow(
        title: "Speech model",
        icon: "waveform",
        state: .blocked,
        detail: "Not downloaded",
        actionTitle: "Prepare",
        action: appModel.prepareModel
      )
    case .failed(let message):
      return StatusRow(
        title: "Speech model",
        icon: "waveform",
        state: .blocked,
        detail: message,
        actionTitle: "Retry",
        action: appModel.prepareModel
      )
    }
  }

  private var provider: StatusRow {
    let settings = appModel.settingsStore.settings
    if settings.privacyMode {
      return StatusRow(
        title: "AI provider",
        icon: "sparkles",
        state: .optional,
        detail: "Off — privacy mode keeps everything on this Mac"
      )
    }
    if !appModel.isCodexCLIInstalled {
      return StatusRow(
        title: "AI provider",
        icon: "sparkles",
        state: .optional,
        detail: "Install and sign in to the Codex CLI to use AI features"
      )
    }
    switch appModel.providerStatus {
    case .failed(let error):
      return StatusRow(
        title: "AI provider",
        icon: "sparkles",
        state: .blocked,
        detail: error.localizedDescription
      )
    case .notConfigured, .readyToAttempt, .retryingCredential:
      return StatusRow(
        title: "AI provider",
        icon: "sparkles",
        state: .ready,
        detail: "Codex CLI · ChatGPT subscription"
      )
    }
  }
}

private struct StatusRow {
  enum State: Equatable {
    case ready
    case working(Double)
    case blocked
    /// Not required for dictation; shown neutrally rather than as a warning.
    case optional
  }

  let title: String
  let icon: String
  let state: State
  let detail: String
  var actionTitle: String?
  var action: (() -> Void)?
}

private struct StatusRowView: View {
  let row: StatusRow

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: row.icon)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 28, height: 28)
        .background(tint.opacity(0.14), in: .rect(cornerRadius: 7))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(row.title)
          .font(.headline)
        Text(row.detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 12)

      switch row.state {
      case .working(let fraction):
        ProgressView(value: fraction)
          .frame(width: 80)
      case .ready:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(MicAIStatusColor.ready)
          .accessibilityHidden(true)
      case .blocked, .optional:
        if let actionTitle = row.actionTitle, let action = row.action {
          Button(actionTitle, action: action)
            .micAISecondaryButtonStyle()
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(row.title): \(row.detail)")
  }

  private var tint: Color {
    switch row.state {
    case .ready:
      MicAIStatusColor.ready
    case .working:
      MicAIStatusColor.accent
    case .blocked:
      MicAIStatusColor.attention
    case .optional:
      .secondary
    }
  }
}
