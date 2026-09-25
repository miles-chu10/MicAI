import Foundation
import MicAICore
import Testing

@Suite
struct SnippetMatcherTests {
  private let signature = Snippet(
    trigger: "My email signature",
    text: "Best,\nMiles"
  )

  @Test
  func wholeUtteranceMatchesIgnoringCaseAndPunctuation() {
    #expect(SnippetMatcher.match("my email signature.", in: [signature]) == signature)
    #expect(SnippetMatcher.match("  My, email signature!  ", in: [signature]) == signature)
  }

  @Test
  func triggerInsideASentenceDoesNotFire() {
    #expect(
      SnippetMatcher.match("please add my email signature at the end", in: [signature])
        == nil
    )
  }

  @Test
  func emptyTranscriptMatchesNothing() {
    #expect(SnippetMatcher.match("  ...  ", in: [signature]) == nil)
  }

  @Test
  func unusableSnippetsNeverMatch() {
    let emptyText = Snippet(trigger: "blank", text: "   ")
    let punctuationTrigger = Snippet(trigger: "?!", text: "x")

    #expect(!emptyText.isUsable)
    #expect(!punctuationTrigger.isUsable)
    #expect(SnippetMatcher.match("blank", in: [emptyText]) == nil)
  }
}

@Suite
struct SnippetStoreTests {
  @Test
  func upsertReplacesTheSnippetWithTheSameSpokenTrigger() async {
    let store = SnippetStore(file: temporaryFile())
    await store.upsert(Snippet(trigger: "office address", text: "1 Old Road"))
    await store.upsert(Snippet(trigger: "Office address.", text: "2 New Road"))

    let all = await store.all()
    #expect(all.count == 1)
    #expect(all.first?.text == "2 New Road")
  }

  @Test
  func snippetsSurviveAReload() async {
    let url = temporaryFile()
    let store = SnippetStore(file: url)
    await store.upsert(Snippet(trigger: "meeting link", text: "https://example.com/m"))

    let reloaded = SnippetStore(file: url)
    await reloaded.load()
    #expect(await reloaded.all().map(\.trigger) == ["meeting link"])
  }

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("snippets-\(UUID().uuidString).json")
  }
}

@Suite
struct UsageStatsTests {
  @Test
  func countsWordsAndAudioAcrossEntries() {
    let stats = UsageStats(entries: [
      entry("One two three four.", seconds: 3),
      entry("Five six.", seconds: 3),
    ])

    #expect(stats.entryCount == 2)
    #expect(stats.wordCount == 6)
    #expect(stats.audioSeconds == 6)
    #expect(stats.wordsPerMinute == 60)
  }

  @Test
  func rateIsWithheldWithTooLittleAudio() {
    let stats = UsageStats(entries: [entry("Hello there.", seconds: 2)])
    #expect(stats.wordsPerMinute == nil)
  }

  @Test
  func minutesSavedNeverGoesNegative() {
    // Four words over two minutes of audio is slower than typing.
    let stats = UsageStats(entries: [entry("a b c d", seconds: 120)])
    #expect(stats.minutesSaved == 0)
  }

  @Test
  func minutesSavedComparesAgainstTheTypingBaseline() {
    // 80 words typed at 40 wpm is two minutes; spoken in 30 seconds.
    let words = Array(repeating: "word", count: 80).joined(separator: " ")
    let stats = UsageStats(entries: [entry(words, seconds: 30)])
    #expect(stats.minutesSaved == 1.5)
  }

  @Test
  func sinceExcludesOlderEntries() {
    let now = Date()
    let stats = UsageStats(
      entries: [
        entry("old words here", seconds: 1, at: now.addingTimeInterval(-86_400 * 10)),
        entry("new", seconds: 1, at: now),
      ],
      since: now.addingTimeInterval(-86_400 * 7)
    )
    #expect(stats.entryCount == 1)
    #expect(stats.wordCount == 1)
  }

  private func entry(
    _ text: String,
    seconds: TimeInterval,
    at date: Date = Date()
  ) -> HistoryEntry {
    HistoryEntry(
      createdAt: date,
      mode: .dictation,
      rawTranscript: text,
      finalText: text,
      audioDuration: seconds
    )
  }
}
