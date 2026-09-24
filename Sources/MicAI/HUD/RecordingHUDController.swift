import AppKit
import Combine
import MicAICore
import SwiftUI

/// Owns the floating panel that hosts the HUD.
///
/// The panel never takes focus and ignores the mouse: it must not steal the
/// cursor from the app you are dictating into, and the transparent area around
/// the pill must not block clicks.
@MainActor
final class RecordingHUDController {
  let model = HUDModel()
  private var panel: NSPanel?
  private var failureDismissTask: Task<Void, Never>?
  private var cancellables: Set<AnyCancellable> = []

  init() {
    model.$phase
      .removeDuplicates()
      .sink { [weak self] phase in
        self?.show(for: phase)
      }
      .store(in: &cancellables)
  }

  func close() {
    failureDismissTask?.cancel()
    failureDismissTask = nil
    panel?.orderOut(nil)
  }

  private func show(for phase: OperationPhase) {
    failureDismissTask?.cancel()

    if phase == .idle {
      close()
      return
    }

    let panel = panel ?? makePanel()
    // Resize to the pill's natural size on every phase change, once SwiftUI
    // has laid out the new content: a failure message is wider than the
    // recording waveform.
    Task { @MainActor [weak self] in
      guard let self, let panel = self.panel, let hostingView = panel.contentView else {
        return
      }
      panel.setContentSize(hostingView.fittingSize)
      self.position(panel)
    }
    position(panel)
    panel.orderFrontRegardless()

    if case .failed = phase {
      failureDismissTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else {
          return
        }
        self?.close()
      }
    }
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 76),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.level = .statusBar
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.ignoresMouseEvents = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    // The pill draws its own soft edge; a window shadow would outline the
    // transparent padding around it.
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let hostingView = NSHostingView(rootView: RecordingHUDView(model: model))
    hostingView.sizingOptions = [.intrinsicContentSize]
    panel.contentView = hostingView
    panel.setContentSize(hostingView.fittingSize)
    self.panel = panel
    return panel
  }

  /// Bottom centre of the screen you are working on, clear of the Dock. The
  /// bottom keeps the HUD away from the menu bar and the notch, and near where
  /// most text fields sit.
  private func position(_ panel: NSPanel) {
    guard let screen = NSScreen.main else {
      return
    }
    let visible = screen.visibleFrame
    let origin = NSPoint(
      x: visible.midX - panel.frame.width / 2,
      y: visible.minY + 28
    )
    panel.setFrameOrigin(origin)
  }
}
