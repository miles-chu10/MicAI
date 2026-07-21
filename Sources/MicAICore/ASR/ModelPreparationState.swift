public enum ModelPreparationState: Sendable, Equatable {
  case notDownloaded
  case preparing(fraction: Double, phase: String)
  case ready
  case failed(String)
}
