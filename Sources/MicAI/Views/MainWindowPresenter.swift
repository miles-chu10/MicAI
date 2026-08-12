import AppKit
import SwiftUI

@MainActor
enum MainWindowPresenter {
  private static let defaultContentSize = NSSize(width: 940, height: 640)
  private static let minimumContentSize = NSSize(width: 760, height: 520)
  private static let windowIdentifier = NSUserInterfaceItemIdentifier(
    "com.mileschu.micai.main-window"
  )
  private static var primaryWindow: NSWindow?

  static func install(appModel: AppModel) {
    if primaryWindow != nil {
      show()
      return
    }

    let rootView: AnyView
    if ProcessInfo.processInfo.environment["MICAI_UI_SURFACE"] == "proof" {
      rootView = AnyView(ProofCenterView(appModel: appModel))
    } else {
      rootView = AnyView(PrimaryAppView(appModel: appModel))
    }
    let hostingController = NSHostingController(
      rootView:
        rootView
        .frame(
          minWidth: minimumContentSize.width,
          idealWidth: defaultContentSize.width,
          maxWidth: .infinity,
          minHeight: minimumContentSize.height,
          idealHeight: defaultContentSize.height,
          maxHeight: .infinity
        )
    )
    hostingController.sizingOptions = []
    hostingController.preferredContentSize = defaultContentSize
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: defaultContentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.title = "MicAI"
    window.contentMinSize = minimumContentSize
    window.toolbarStyle = .unified
    window.setContentSize(defaultContentSize)
    window.center()
    register(window)
    primaryWindow = window
    show()

    DispatchQueue.main.async {
      guard primaryWindow === window else { return }
      hostingController.view.layoutSubtreeIfNeeded()
      window.setContentSize(defaultContentSize)
      window.center()
      show()
    }
  }

  static func show() {
    _ = focusExistingMainWindow()
  }

  private static func register(_ window: NSWindow) {
    window.identifier = windowIdentifier
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
  }

  @discardableResult
  static func focusExistingMainWindow() -> Bool {
    guard
      let window = primaryWindow
        ?? NSApplication.shared.windows.first(where: {
          $0.identifier == windowIdentifier
        })
    else {
      return false
    }

    primaryWindow = window
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
    _ = NSRunningApplication.current.activate(
      options: [.activateAllWindows]
    )

    // Reassert focus after AppKit finishes the current launch/reopen event. This
    // is especially important for an LSUIElement app, where the menu-bar scene
    // can finish activating after the primary window is first ordered.
    DispatchQueue.main.async {
      guard primaryWindow === window else { return }
      window.makeKeyAndOrderFront(nil)
      _ = NSRunningApplication.current.activate(
        options: [.activateAllWindows]
      )
    }
    return true
  }
}
