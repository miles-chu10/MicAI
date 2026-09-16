import Foundation
import MicAICore
import Testing

@Suite
struct VocabularyApplierTests {
  private let applier = VocabularyApplier()

  @Test
  func replacesWholeWordsCaseInsensitively() {
    let entries = [VocabularyEntry(heard: "paraquet", written: "Parakeet")]
    let result = applier.apply("the Paraquet model is fast", entries: entries)

    #expect(result.text == "the Parakeet model is fast")
    #expect(result.appliedEntryIDs == [entries[0].id])
  }

  @Test
  func doesNotReplaceInsideLargerWords() {
    let entries = [VocabularyEntry(heard: "ai", written: "AI")]
    let result = applier.apply("said the maid quietly", entries: entries)

    #expect(result.text == "said the maid quietly")
    #expect(result.appliedEntryIDs.isEmpty)
  }

  @Test
  func longerPhraseWinsOverItsOwnPrefix() {
    let entries = [
      VocabularyEntry(heard: "micro AI", written: "MicAI"),
      VocabularyEntry(heard: "micro", written: "Micro"),
    ]
    let result = applier.apply("open micro AI now", entries: entries)

    #expect(result.text == "open MicAI now")
  }

  @Test
  func ignoresNoOpAndEmptyEntries() {
    let entries = [
      VocabularyEntry(heard: "slack", written: "Slack"),
      VocabularyEntry(heard: "  ", written: "nothing"),
      VocabularyEntry(heard: "same", written: "SAME"),
    ]
    let result = applier.apply("post to slack about same", entries: entries)

    #expect(result.text == "post to Slack about same")
    #expect(result.appliedEntryIDs.count == 1)
  }

  @Test
  func replacementTextIsNotTreatedAsARegexTemplate() {
    // A "$1" in the replacement must land literally, not as a capture group.
    let entries = [VocabularyEntry(heard: "cost", written: "$1 cost")]
    let result = applier.apply("the cost went up", entries: entries)

    #expect(result.text == "the $1 cost went up")
  }

  @Test
  func promptContextIsNilWhenNothingIsUsable() {
    #expect(applier.promptContext(entries: []) == nil)
    #expect(applier.promptContext(entries: [VocabularyEntry(heard: "a", written: "a")]) == nil)
  }

  @Test
  func promptContextPrefersMostUsedEntriesAndRespectsLimit() {
    let entries = (0..<10).map { index in
      VocabularyEntry(
        heard: "heard\(index)",
        written: "written\(index)",
        hitCount: index
      )
    }
    let context = applier.promptContext(entries: entries, limit: 2)

    #expect(context?.contains("heard9") == true)
    #expect(context?.contains("heard8") == true)
    #expect(context?.contains("heard0") == false)
  }
}

@Suite
struct VocabularyLearnerTests {
  private let learner = VocabularyLearner()

  @Test
  func learnsASingleMisheardWord() {
    let proposals = learner.proposals(
      original: "the paraquet model is fast",
      corrected: "the Parakeet model is fast"
    )

    #expect(proposals.count == 1)
    #expect(proposals.first?.heard == "paraquet")
    #expect(proposals.first?.written == "Parakeet")
  }

  @Test
  func ignoresPureInsertionsAndDeletions() {
    // Adding or cutting words teaches nothing about how a term is heard.
    #expect(learner.proposals(original: "ship it", corrected: "ship it today").isEmpty)
    #expect(learner.proposals(original: "ship it today", corrected: "ship it").isEmpty)
  }

  @Test
  func ignoresWholesaleRewrites() {
    let proposals = learner.proposals(
      original: "one two three four five",
      corrected: "completely different words entirely here"
    )

    #expect(proposals.isEmpty)
  }

  @Test
  func stripsSurroundingPunctuationSoOneProposalIsProduced() {
    let proposals = learner.proposals(
      original: "we use paraquet.",
      corrected: "we use Parakeet."
    )

    #expect(proposals.count == 1)
    #expect(proposals.first?.heard == "paraquet")
    #expect(proposals.first?.written == "Parakeet")
  }

  @Test
  func identicalTextProducesNoProposals() {
    #expect(learner.proposals(original: "all good", corrected: "all good").isEmpty)
  }

  @Test
  func caseOnlyChangeIsNotAProposal() {
    // The diff matches case-insensitively, so this aligns with no replacement
    // block — capitalization is refinement's job, not vocabulary's.
    #expect(learner.proposals(original: "slack thread", corrected: "Slack thread").isEmpty)
  }
}
