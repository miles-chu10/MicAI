public protocol SpeechRecognizing: Sendable {
  func prepare(
    progress: @escaping @Sendable (ModelPreparationState) -> Void
  ) async throws

  func transcribe(samples: [Float]) async throws -> Transcript
}
