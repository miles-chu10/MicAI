import MicAICore
import SwiftUI

enum PrimarySection: String, CaseIterable, Identifiable {
  case overview
  case dictation
  case commands
  case proof
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
    case .proof:
      "Proof"
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
    case .proof:
      "checkmark.shield"
    case .activity:
      "clock"
    }
  }
}

struct PrimaryAppView: View {
  @ObservedObject var appModel: AppModel
  @State private var selection: PrimarySection? = .overview

  init(appModel: AppModel) {
    self.appModel = appModel
    _selection = State(
      initialValue: appModel.pendingProofDraft == nil ? .overview : .proof
    )
  }

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
    .onChange(of: appModel.recoverableInsertion?.id) { _, recoveryID in
      if recoveryID != nil {
        selection = .activity
      }
    }
    .onChange(of: appModel.pendingProofDraft?.id) { _, draftID in
      if draftID != nil {
        selection = .proof
      }
    }
  }

  @ViewBuilder
  private var detail: some View {
    switch selection ?? .overview {
    case .overview:
      OverviewView(appModel: appModel) { section in
        selection = section
      }
    case .dictation:
      DictationView(appModel: appModel)
    case .commands:
      CommandsView(appModel: appModel)
    case .proof:
      ProofCenterView(appModel: appModel)
    case .activity:
      ActivityView(appModel: appModel)
    }
  }

  private var readinessFooter: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()
      Label {
        Text(sidebarReadinessTitle)
      } icon: {
        Image(systemName: sidebarReadinessIcon)
          .foregroundStyle(sidebarReadinessTint)
      }
      .font(.callout)

      if appModel.readiness.dictation.hasPendingRecovery {
        Button {
          selection = appModel.pendingProofDraft == nil ? .activity : .proof
        } label: {
          Label(
            appModel.pendingProofDraft == nil
              ? "Resolve Saved Result" : "Review Proof Draft",
            systemImage: appModel.pendingProofDraft == nil
              ? "doc.badge.clock" : "checkmark.shield"
          )
        }
        .buttonStyle(.link)
        .controlSize(.small)
      } else {
        Button {
          appModel.showOnboarding()
        } label: {
          Label(
            appModel.readiness.dictation.isSetupReady ? "Review Setup" : "Finish Setup",
            systemImage: "checklist"
          )
        }
        .buttonStyle(.link)
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
  }
  private var sidebarReadinessTitle: String {
    if appModel.pendingProofDraft != nil {
      return "Proof draft needs approval"
    }
    if appModel.readiness.dictation.hasPendingRecovery {
      return "Saved result needs attention"
    }
    if appModel.readiness.dictation.isBusy {
      return "MicAI is busy"
    }
    return appModel.readiness.dictation.isSetupReady
      ? "Dictation ready" : "Setup required"
  }

  private var sidebarReadinessIcon: String {
    if appModel.pendingProofDraft != nil {
      return "checkmark.shield"
    }
    if appModel.readiness.dictation.hasPendingRecovery {
      return "doc.badge.clock"
    }
    if appModel.readiness.dictation.isBusy {
      return "hourglass.circle.fill"
    }
    return appModel.readiness.dictation.isSetupReady
      ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
  }

  private var sidebarReadinessTint: Color {
    if appModel.readiness.dictation.hasPendingRecovery {
      return MicAIStatusColor.attention
    }
    if appModel.readiness.dictation.isBusy {
      return .accentColor
    }
    return appModel.readiness.dictation.isSetupReady
      ? MicAIStatusColor.ready : MicAIStatusColor.attention
  }
}

private struct DictationView: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        FeatureHeader(
          icon: "mic.fill",
          title: "Dictation",
          subtitle:
            "\(appModel.dictationSelectedRouteLabel) is selected. "
            + "Effective now: \(appModel.dictationEffectiveRouteLabel)."
        )
        GroupBox("Transcription route") {
          VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Selected") {
              Text(appModel.dictationSelectedRouteLabel)
                .multilineTextAlignment(.trailing)
            }
            LabeledContent("Effective now") {
              Text(appModel.dictationEffectiveRouteLabel)
                .multilineTextAlignment(.trailing)
            }
            Label(
              appModel.dictationProviderStatus.summary,
              systemImage: appModel.isDictationProviderReady
                ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .foregroundStyle(
              appModel.isDictationProviderReady
                ? MicAIStatusColor.ready : MicAIStatusColor.attention
            )
            SettingsLink {
              Label("Review Transcription Settings", systemImage: "gearshape")
            }
          }
          .padding(.vertical, 6)
        }
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
            Text(
              "4. MicAI stops at 2 minutes, then sends the completed recording "
                + "through the effective transcription route."
            )
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        }
        GroupBox("Parakeet on-device model") {
          ModelStatusView(
            state: appModel.modelState,
            transcript: nil,
            prepare: appModel.prepareModel
          )
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          Text(
            "Parakeet is always used for AI Command speech and can provide "
              + "the offline fallback for ordinary dictation."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
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
            "Personal-use preview: only your instruction and selected text are sent through your local Codex sign-in."
        )
        ReadinessList(
          readiness: appModel.readiness.command,
          reviewSetup: appModel.showOnboarding
        )
        GroupBox("Provider") {
          VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Experimental personal route") {
              Text(appModel.providerStatus.summary)
                .multilineTextAlignment(.trailing)
            }
            Text(
              "This is a personal prototype integration, not a supported public OpenAI API authentication method."
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
          "AI Commands are hold-to-talk and stop automatically at 2 minutes. Select text first to replace it; with no selection, the result is inserted at the cursor."
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

      if let recovery = appModel.recoverableInsertion {
        RecoveryResultView(appModel: appModel, recovery: recovery)
      }

      if let transcript = appModel.lastTranscript {
        GroupBox("Most recent result") {
          Text(transcript)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
      } else if appModel.recoverableInsertion == nil {
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
    GroupBox(groupTitle) {
      if !readiness.isSetupReady {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(readiness.setupBlockers, id: \.self) { blocker in
            Label {
              Text(blocker.message)
            } icon: {
              Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(MicAIStatusColor.attention)
            }
          }
          Divider()
          Button("Review Setup", systemImage: "checklist", action: reviewSetup)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      } else if readiness.hasPendingRecovery {
        Label {
          Text("Retry, copy, or dismiss the saved result in Activity before recording again.")
        } icon: {
          Image(systemName: "doc.badge.clock")
            .foregroundStyle(MicAIStatusColor.attention)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      } else if readiness.isBusy {
        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
          Text("Another MicAI operation is in progress. Wait or press Escape to cancel.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
      } else {
        Label {
          Text("All required services are ready.")
        } icon: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(MicAIStatusColor.ready)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      }
    }
  }

  private var groupTitle: String {
    if !readiness.isSetupReady {
      return "Before you begin"
    }
    if readiness.hasPendingRecovery {
      return "Result needs attention"
    }
    return readiness.isBusy ? "Busy" : "Ready"
  }
}
