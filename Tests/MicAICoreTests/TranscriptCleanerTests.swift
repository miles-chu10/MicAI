import MicAICore
import Testing

@Suite
struct TranscriptCleanerTests {
  private let cleaner = TranscriptCleaner()

  @Test
  func trimsOuterWhitespace() {
    #expect(cleaner.clean("  hello world \n") == "hello world")
  }

  @Test
  func collapsesHorizontalWhitespace() {
    #expect(cleaner.clean("hello\t   world") == "hello world")
  }

  @Test
  func normalizesWhitespaceAroundNewlinesWithoutRephrasing() {
    #expect(cleaner.clean("first  \n \tsecond\n\nthird") == "first\nsecond\n\nthird")
  }

  @Test
  func preservesWordsAndPunctuation() {
    #expect(cleaner.clean("Keep THIS, exactly!") == "Keep THIS, exactly!")
  }
}
