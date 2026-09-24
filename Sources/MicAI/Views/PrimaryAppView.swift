import MicAICore
import SwiftUI

private enum PrimarySection: String, CaseIterable, Identifiable {
  case overview
  case dictation
  case commands
  case activity

  var id: Self { self }

  var title: String {
    switch self {
    case .overview:
      "Overview"
    case .dictation:
      "Dictation"
    case .commands:
      "AI Commands"
    case .activity:
      "Activity"
    }
  }

  var systemImage: String {
    switch self {
    case .overview:
      "square.grid.2x2"
    case .dictation:
      "mic"
    case .commands:
      "sparkles"
    case .activity:
      "clock"
    }
  }
}

struct PrimaryAppView: View {
  @ObservedObject var appModel: AppModel
  @State private var selection: PrimarySection? = .overview

  var body: some View {
    NavigationSplitView {
      List(PrimarySection.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationTitle("MicAI")
      .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
      .safeAreaInset(edge: .bottom) {
        readinessFooter
      }
    } detail: {
      detail
        .navigationTitle(selection?.title ?? "Overview")
        .toolbar {
          ToolbarItem(placement: .automatic) {
            StatusPill(phase: appModel.operationPhase)
          }
          ToolbarItem(placement: .primaryAction) {
            SettingsLink {
              Label("Settings", systemImage: "gearshape")
            }
          }
        }
        .sheet(isPresented: $appModel.isOnboardingPresented) {
          OnboardingView(appModel: appModel)
        }
    }
  }

  @ViewBuilder
  private var detail: some View {
    switch selection ?? .overview {
    case .overview:
      OverviewView(appModel: appModel)
    case .dictation:
      DictationView(appModel: appModel)
    case .commands:
      CommandsView(appModel: appModel)
    case .activity:
      ActivityView(appModel: appModel)
    }
  }

  private var readinessFooter: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      Label(
        appModel.readiness.dictation.isReady ? "Dictation ready" : "Setup required",
        systemImage: appModel.readiness.dictation.isReady
          ? "checkmark.circle.fill" : "exclamationmark.circle"
      )
      .font(.caption)
      .foregroundStyle(
        appModel.readiness.dictation.isReady ? MicAIStatusColor.ready : Color.secondary
      )
      Button("Review Setup") {
        appModel.showOnboarding()
      }
      .buttonStyle(.link)
      .font(.caption)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
  }
}

private struct OverviewView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Speak where you work")
            .font(.largeTitle.weight(.semibold))
          Text(
            "MicAI transcribes dictation locally and uses ChatGPT only for explicit AI Commands."
          )
          .font(.title3)
          .foregroundStyle(.secondary)
        }

        HStack(alignment: .top, spacing: 16) {
          WorkflowCard(
            title: "Dictation",
            icon: "mic.fill",
            shortcut: appModel.settingsStore.settings.dictationHotkey.displayName,
            ready: appModel.readiness.dictation,
            detail: "Hold or toggle the hotkey, speak, then let MicAI paste at the original cursor."
          )
          WorkflowCard(
            title: "AI Commands",
            icon: "sparkles",
            shortcut: appModel.settingsStore.settings.commandHotkey?.displayName
              ?? "Not configured",
            ready: appModel.readiness.command,
            detail: "Select text and speak an instruction, or draft new text at the cursor."
          )
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("System status")
            .font(.headline)
          PermissionStatusView(appModel: appModel)
        }

        if let errorMessage = appModel.errorMessage {
          Label {
            Text(errorMessage)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(MicAIStatusColor.attention)
          }
          .micAINoticeSurface(tint: MicAIStatusColor.attention)
        }

        if !appModel.settingsStore.hasSeenOnboarding
          || !appModel.readiness.dictation.isReady
        {
          Button("Complete Setup", systemImage: "checklist") {
            appModel.showOnboarding()
          }
          .micAIPrimaryButtonStyle()
          .controlSize(.large)
        }
      }
      .padding(32)
      .frame(maxWidth: 900, alignment: .leading)
    }
  }
}

private struct WorkflowCard: View {
  let title: String
  let icon: String
  let shortcut: String
  let ready: FeatureReadiness
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: icon)
        .font(.title2.weight(.semibold))
      Text(shortcut)
        .font(.system(.headline, design: .rounded))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary, in: .rect(cornerRadius: 7))
      Text(detail)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Label(
        ready.isReady ? "Ready" : "\(ready.blockers.count) setup item(s)",
        systemImage: ready.isReady ? "checkmark.circle.fill" : "circle.dashed"
      )
      .foregroundStyle(ready.isReady ? MicAIStatusColor.ready : Color.secondary)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
    .micAICardSurface(cornerRadius: 14)
  }
}

private struct DictationView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        FeatureHeader(
          icon: "mic.fill",
          title: "Local dictation",
          subtitle: "Audio stays on this Mac and is transcribed with Parakeet TDT v2."
        )
        ReadinessList(readiness: appModel.readiness.dictation)
        GroupBox("How to dictate") {
          VStack(alignment: .leading, spacing: 10) {
            Text(
              "1. Place the cursor in TextEdit, Mail, a browser, or another text field."
            )
            Text(
              "2. \(instructionForDictation(appModel.settingsStore.settings))."
            )
            Text("3. Press Escape before paste to cancel without inserting.")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        }
        ModelStatusView(
          state: appModel.modelState,
          transcript: nil,
          prepare: appModel.prepareModel
        )
      }
      .padding(32)
      .frame(maxWidth: 760, alignment: .leading)
    }
  }

  private func instructionForDictation(_ settings: AppSettings) -> String {
    switch settings.dictationActivationMode {
    case .hold:
      "Hold \(settings.dictationHotkey.displayName), speak, and release"
    case .toggle:
      "Press \(settings.dictationHotkey.displayName) once to start and again to stop"
    }
  }
}

private struct CommandsView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        FeatureHeader(
          icon: "sparkles",
          title: "AI Commands",
          subtitle:
            "Your instruction and selected text run ephemerally through your signed-in Codex CLI."
        )
        ReadinessList(readiness: appModel.readiness.command)
        GroupBox("Provider") {
          LabeledContent("Codex CLI · ChatGPT subscription") {
            Text(appModel.providerStatus.summary)
              .multilineTextAlignment(.trailing)
          }
          .padding(.vertical, 6)
        }
        GroupBox("Examples") {
          VStack(alignment: .leading, spacing: 8) {
            Text("“Make this more formal”")
            Text("“Turn this into bullet points”")
            Text("“Reply agreeing and propose Tuesday”")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        }
        Text(
          "AI Commands are hold-to-talk. Select text first to replace it; with no selection, the result is inserted at the cursor."
        )
        .foregroundStyle(.secondary)
      }
      .padding(32)
      .frame(maxWidth: 760, alignment: .leading)
    }
  }
}

private struct ActivityView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      FeatureHeader(
        icon: "clock",
        title: "Current session",
        subtitle:
          "Your latest result and how long MicAI took. Audio is never kept; saved text is in History."
      )

      if !appModel.metrics.timings.isEmpty {
        PerformanceSummary(metrics: appModel.metrics)
      }

      if let transcript = appModel.lastTranscript {
        GroupBox("Most recent local result") {
          Text(transcript)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
      } else {
        ContentUnavailableView(
          "No activity yet",
          systemImage: "waveform",
          description: Text("Your most recent result will appear here for this session.")
        )
      }
      Spacer()
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct PerformanceSummary: View {
  let metrics: LocalMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Release to insertion")
        .font(.headline)
      HStack(spacing: 12) {
        ForEach(MicAIMode.allCases, id: \.self) { mode in
          if let median = metrics.median(for: mode), let worst = metrics.worst(for: mode) {
            VStack(alignment: .leading, spacing: 4) {
              Label(mode.displayName, systemImage: "timer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MicAIStatusColor.modeTint(mode))
              Text(Self.format(median))
                .font(.title2.weight(.semibold).monospacedDigit())
              Text("median · worst \(Self.format(worst))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .micAICardSurface()
          }
        }
      }
      Text("Last \(metrics.timings.count) operations this session. Kept in memory only.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private static func format(_ duration: Duration) -> String {
    duration.formatted(
      .units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 2)))
  }
}

private struct FeatureHeader: View {
  let icon: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 28))
        .foregroundStyle(.tint)
        .frame(width: 42, height: 42)
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.title.weight(.semibold))
        Text(subtitle)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct ReadinessList: View {
  let readiness: FeatureReadiness

  var body: some View {
    GroupBox(readiness.isReady ? "Ready" : "Before you begin") {
      if readiness.isReady {
        Label("All required services are ready.", systemImage: "checkmark.circle.fill")
          .foregroundStyle(MicAIStatusColor.ready)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(readiness.blockers, id: \.self) { blocker in
            Label {
              Text(blocker.message)
            } icon: {
              Image(systemName: "exclamationmark.circle")
                .foregroundStyle(MicAIStatusColor.attention)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      }
    }
  }
}
