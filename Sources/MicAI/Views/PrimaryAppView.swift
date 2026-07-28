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
        appModel.readiness.dictation.isReady ? Color.green : Color.secondary
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

        if let errorMessage = appModel.errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        }

        if !appModel.settingsStore.hasSeenOnboarding
          || !appModel.readiness.dictation.isReady
        {
          Button("Complete Setup") {
            appModel.showOnboarding()
          }
          .buttonStyle(.borderedProminent)
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
      .foregroundStyle(ready.isReady ? Color.green : Color.secondary)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
    .background(.background, in: .rect(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(.separator, lineWidth: 1)
    }
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
            "Only your spoken instruction and selected text are sent to the configured ChatGPT route."
        )
        ReadinessList(readiness: appModel.readiness.command)
        GroupBox("Provider") {
          LabeledContent("ChatGPT subscription") {
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
        subtitle: "MicAI does not persist transcription history or audio."
      )

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
          .foregroundStyle(.green)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(readiness.blockers, id: \.self) { blocker in
            Label(blocker.message, systemImage: "circle")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      }
    }
  }
}
