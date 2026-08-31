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
      .listStyle(.sidebar)
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
    .navigationSplitViewStyle(.balanced)
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
    VStack(alignment: .leading, spacing: 10) {
      Divider()
      Label {
        Text(
          appModel.readiness.dictation.isReady
            ? "Dictation ready" : "Setup required"
        )
      } icon: {
        Image(
          systemName: appModel.readiness.dictation.isReady
            ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .foregroundStyle(
          appModel.readiness.dictation.isReady ? Color.green : Color.orange
        )
      }
      .font(.callout)

      Button {
        appModel.showOnboarding()
      } label: {
        Label(
          appModel.readiness.dictation.isReady ? "Review Setup" : "Finish Setup",
          systemImage: "checklist"
        )
      }
      .buttonStyle(.link)
      .controlSize(.small)
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 14)
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

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 260), spacing: 16)],
          alignment: .leading,
          spacing: 16
        ) {
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

        GroupBox {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
              .font(.title2)
              .foregroundStyle(.tint)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
              Text("Private by default")
                .font(.headline)
              Text(
                "Ordinary dictation stays on this Mac. MicAI contacts ChatGPT only when you explicitly invoke an AI Command."
              )
              .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
        }

        if let errorMessage = appModel.errorMessage {
          Label {
            Text(errorMessage)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        }

        if !appModel.settingsStore.hasSeenOnboarding
          || !appModel.readiness.dictation.isReady
        {
          Button("Complete Setup", systemImage: "checklist") {
            appModel.showOnboarding()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
      }
      .padding(28)
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
        .font(.title3.bold())
      Text(shortcut)
        .font(.system(.callout, design: .rounded).bold())
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary, in: .rect(cornerRadius: 7))
      Text(detail)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      if ready.isReady {
        Label {
          Text("Ready")
        } icon: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      } else {
        Label {
          Text("^[\(ready.blockers.count) setup item](inflect: true)")
        } icon: {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.orange)
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
    .background(.background, in: .rect(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(.separator, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
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
        ReadinessList(
          readiness: appModel.readiness.dictation,
          reviewSetup: appModel.showOnboarding
        )
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
        GroupBox("Local speech model") {
          ModelStatusView(
            state: appModel.modelState,
            transcript: nil,
            prepare: appModel.prepareModel
          )
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(28)
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
        ReadinessList(
          readiness: appModel.readiness.command,
          reviewSetup: appModel.showOnboarding
        )
        GroupBox("Provider") {
          VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Authentication", value: "ChatGPT sign-in")
            LabeledContent("Status") {
              Text(appModel.providerStatus.summary)
                .multilineTextAlignment(.trailing)
            }
            Text(
              "Subscription access comes from your existing Codex sign-in with ChatGPT."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
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
      .padding(28)
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
    .padding(28)
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
        .font(.title2)
        .foregroundStyle(.tint)
        .padding(10)
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.title.weight(.semibold))
        Text(subtitle)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct ReadinessList: View {
  let readiness: FeatureReadiness
  let reviewSetup: () -> Void

  var body: some View {
    GroupBox(readiness.isReady ? "Ready" : "Before you begin") {
      if readiness.isReady {
        Label {
          Text("All required services are ready.")
        } icon: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(readiness.blockers, id: \.self) { blocker in
            Label {
              Text(blocker.message)
            } icon: {
              Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            }
          }
          Divider()
          Button("Review Setup", systemImage: "checklist", action: reviewSetup)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      }
    }
  }
}
