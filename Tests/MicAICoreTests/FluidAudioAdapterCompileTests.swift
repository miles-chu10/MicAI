import MicAICore
import Testing

@Test
func fluidAudioAdapterConformsToSpeechRecognizing() async {
  let recognizer: any SpeechRecognizing = FluidAudioRecognizer()
  let state = await (recognizer as? FluidAudioRecognizer)?.state()

  #expect(state == .notDownloaded)
}
