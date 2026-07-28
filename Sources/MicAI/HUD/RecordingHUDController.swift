import AppKit
import Combine
import MicAICore
import SwiftUI

@MainActor
final class RecordingHUDController: ObservableObject {
  private var panel: NSPanel?
  private var failureDismissTask: Task<Void, Never>?

  func update(
    phase: OperationPhase,
    level: Float,
    message: String?
  ) {
    failureDismissTask?.cancel()

    if phase == .idle {
      close()
      return
    }

    let panel = panel ?? makePanel()
    let view = RecordingHUDView(
      phase: phase,
      inputLevel: level,
      message: message
    )
    if let hostingView = panel.contentView as? NSHostingView<RecordingHUDView> {
      hostingView.rootView = view
    } else {
      panel.contentView = NSHostingView(rootView: view)
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

  func close() {
    failureDismissTask?.cancel()
    failureDismissTask = nil
    panel?.orderOut(nil)
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 104),
      styleMask: [.nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovableByWindowBackground = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    self.panel = panel
    return panel
  }

  private func position(_ panel: NSPanel) {
    guard let screen = NSScreen.main else {
      return
    }
    let visible = screen.visibleFrame
    let origin = NSPoint(
      x: visible.midX - panel.frame.width / 2,
      y: visible.maxY - panel.frame.height - 24
    )
    panel.setFrameOrigin(origin)
  }
}
