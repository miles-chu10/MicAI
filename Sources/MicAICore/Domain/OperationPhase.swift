public enum OperationPhase: Sendable, Equatable {
  case idle
  case recording
  case transcribing
  case awaitingLLM
  case inserting
  case failed(MicAIError)
}
