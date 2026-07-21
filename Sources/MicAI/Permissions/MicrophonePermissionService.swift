@preconcurrency import AVFoundation
import Combine

enum MicrophonePermissionStatus: Equatable {
  case undetermined
  case denied
  case granted
}

@MainActor
final class MicrophonePermissionService: ObservableObject {
  @Published private(set) var status: MicrophonePermissionStatus

  init() {
    status = Self.currentStatus
  }

  var isGranted: Bool {
    status == .granted
  }

  func refresh() {
    status = Self.currentStatus
  }

  func request() async -> Bool {
    let granted = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    status = granted ? .granted : .denied
    return granted
  }

  private static var currentStatus: MicrophonePermissionStatus {
    switch AVAudioApplication.shared.recordPermission {
    case .undetermined:
      .undetermined
    case .denied:
      .denied
    case .granted:
      .granted
    @unknown default:
      .denied
    }
  }
}
