import Combine
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
  case disabled
  case enabled
  case requiresApproval
  case unavailable

  var label: String {
    switch self {
    case .disabled:
      "Off"
    case .enabled:
      "On"
    case .requiresApproval:
      "Needs approval in Login Items"
    case .unavailable:
      "Unavailable"
    }
  }
}

@MainActor
final class LaunchAtLoginService: ObservableObject {
  @Published private(set) var status: LaunchAtLoginStatus = .disabled
  @Published private(set) var errorMessage: String?

  init() {
    refresh()
  }

  var isEnabled: Bool {
    status == .enabled || status == .requiresApproval
  }

  func refresh() {
    switch SMAppService.mainApp.status {
    case .notRegistered:
      status = .disabled
    case .enabled:
      status = .enabled
    case .requiresApproval:
      status = .requiresApproval
    case .notFound:
      status = .unavailable
    @unknown default:
      status = .unavailable
    }
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    refresh()
  }
}
