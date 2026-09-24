import AppKit
import Combine
import MicAICore
import SwiftUI

@MainActor
final class RecordingHUDController: ObservableObject {
  private var panel: NSPanel?
  private var failureDismissTask: Task<Void, Never>?

  func update(
    mode: MicAIMode?,
    phase: OperationPhase,
    level: Float,
    message: String?
  ) {
    failureDismissTask?.cancel()

    if phase == .idle {
      close()
      return
    }

    let shouldPosition = panel?.isVisible != true
    let panel = panel ?? makePanel()
    let view = RecordingHUDView(
      mode: mode,
      phase: phase,
      inputLevel: level,
      message: message
    )
    if let hostingView = panel.contentView as? NSHostingView<RecordingHUDView> {
      hostingView.rootView = view
    } else {
      panel.contentView = NSHostingView(rootView: view)
    }
    if shouldPosition {
      position(panel)
    }
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
      contentRect: NSRect(x: 0, y: 0, width: 328, height: 72),
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
    panel.animationBehavior = .utilityWindow
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    self.panel = panel
    return panel
  }

  private func position(_ panel: NSPanel) {
    let pointer = NSEvent.mouseLocation
    guard
      let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
        ?? NSScreen.main
    else {
      return
    }
    let visible = screen.visibleFrame
    let origin = NSPoint(
      x: visible.midX - panel.frame.width / 2,
      y: visible.minY + 44
    )
    panel.setFrameOrigin(origin)
  }
}
