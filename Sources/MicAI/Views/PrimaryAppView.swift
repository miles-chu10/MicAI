import MicAICore
import SwiftUI

/// The main window: what MicAI can do, whether it is ready, and what it has
/// done lately. Configuration lives in Settings; this page is for glancing.
struct PrimaryAppView: View {
  @ObservedObject var appModel: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        if !appModel.readiness.dictation.isReady {
          SetupBanner(appModel: appModel)
        }

        section("Shortcuts") {
          LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
            spacing: 14
          ) {
            ForEach(MicAIMode.allCases, id: \.self) { mode in
              ModeCard(
                mode: mode,
                hotkey: appModel.settingsStore.settings.hotkey(for: mode),
                availability: availability(for: mode)
              )
            }
          }
        }

        section("This week") {
          UsageSummary(stats: appModel.usage(since: HistoryView.weekStart))
            .clipShape(.rect(cornerRadius: 10))
        }

        section("Recent") {
          if appModel.historyEntries.isEmpty {
            Text(
              appModel.settingsStore.settings.historyEnabled
                ? "Nothing yet. What you dictate will show up here."
                : "History is off in Settings › Privacy."
            )
            .foregroundStyle(.secondary)
          } else {
            VStack(spacing: 0) {
              ForEach(appModel.historyEntries.prefix(5)) { entry in
                RecentRow(entry: entry)
                if entry.id != appModel.historyEntries.prefix(5).last?.id {
                  Divider()
                }
              }
            }
            .padding(.horizontal, 14)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
            Button("Open History") {
              openWindow(id: "history")
            }
            .buttonStyle(.link)
          }
        }
      }
      .padding(28)
      .frame(maxWidth: 820, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("MicAI")
    .toolbar {
      ToolbarItem(placement: .status) {
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

  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      content()
    }
  }

  /// Why a mode would not run right now, or nil when it would.
  private func availability(for mode: MicAIMode) -> String? {
    let settings = appModel.settingsStore.settings
    if settings.hotkey(for: mode) == nil {
      return "Off"
    }
    guard mode != .dictation else {
      return appModel.readiness.dictation.isReady ? nil : "Finish setup"
    }
    if settings.privacyMode {
      return "Paused in privacy mode"
    }
    if settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Needs a model"
    }
    if mode == .translate,
      settings.translationTargetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return "Needs a language"
    }
    return nil
  }
}

private struct ModeCard: View {
  let mode: MicAIMode
  let hotkey: Hotkey?
  let availability: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: mode.symbol)
          .font(.title3)
          .foregroundStyle(mode.tint)
          .frame(width: 32, height: 32)
          .background(mode.tint.opacity(0.14), in: .rect(cornerRadius: 8))
          .accessibilityHidden(true)
        Spacer()
        if let hotkey {
          KeyCaps(hotkey)
        }
      }
      Text(mode.shortName)
        .font(.headline)
      Text(mode.summary)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Label(
        availability ?? "Ready",
        systemImage: availability == nil ? "checkmark.circle.fill" : "circle.dashed"
      )
      .font(.caption)
      .foregroundStyle(availability == nil ? Color.green : Color.secondary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
    .background(.background.secondary, in: .rect(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.separator, lineWidth: 0.5)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct RecentRow: View {
  let entry: HistoryEntry

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      ModeDot(mode: entry.mode)
      Text(entry.preview)
        .lineLimit(1)
      Spacer()
      Text(entry.applicationName ?? "")
        .foregroundStyle(.secondary)
      Text(entry.createdAt, style: .time)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .font(.callout)
    .padding(.vertical, 9)
  }
}

private struct SetupBanner: View {
  @ObservedObject var appModel: AppModel

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.title2)
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text("Finish setting up MicAI")
          .font(.headline)
        Text(appModel.readiness.dictation.blockers.map(\.message).joined(separator: " "))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Continue Setup") {
        appModel.showOnboarding()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(16)
    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
  }
}
