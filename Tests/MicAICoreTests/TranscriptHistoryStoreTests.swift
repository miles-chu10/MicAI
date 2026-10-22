import Foundation
import MicAICore
import Testing

@Suite
struct TranscriptHistoryStoreTests {
  @Test
  func loweringTheLimitTrimsTheOldestEntriesStraightAway() async throws {
    let store = try makeStore(limit: 5)
    for index in 1...4 {
      await store.record(entry("entry \(index)"))
    }

    await store.setLimit(2)

    let kept = await store.all().map(\.finalText)
    #expect(kept == ["entry 4", "entry 3"])
  }

  @Test
  func raisingTheLimitKeepsMoreFromThenOn() async throws {
    let store = try makeStore(limit: 1)
    await store.record(entry("first"))

    await store.setLimit(3)
    await store.record(entry("second"))

    #expect(await store.all().count == 2)
  }

  private func makeStore(limit: Int) throws -> TranscriptHistoryStore {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MicAITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return TranscriptHistoryStore(
      file: directory.appendingPathComponent("history.json"),
      limit: limit
    )
  }

  private func entry(_ text: String) -> HistoryEntry {
    HistoryEntry(
      mode: .dictation,
      rawTranscript: text,
      finalText: text,
      applicationName: nil,
      bundleIdentifier: nil,
      audioDuration: 1,
      refined: false
    )
  }
}
