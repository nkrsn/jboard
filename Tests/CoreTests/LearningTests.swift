import XCTest
@testable import JBoardCore

final class LearningTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!
    var learned: LearnedWordPairs!
    var doc: MockDocument!
    var settings: KeyboardSettings!
    var engine: InputController!
    override func setUp() {
        suite = "LearningTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        learned = LearnedWordPairs(defaults: defaults)
        doc = MockDocument(); settings = KeyboardSettings(defaults: defaults)
        engine = InputController(document: doc, candidates: CandidateService(
            lexicons: [FrequencyLexicon(entries: ["tank": 100])],
            nextWords: WordPairPredictor(pairs: ["aeration": ["system", "tank", "process"]]),
            learnedPairs: learned), settings: settings, learnedPairs: learned)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func type(_ text: String) { for c in text { engine.type(String(c)) } }
    func testTypingLearnsAndPersistsWithPersonalPriority() {
        type("aeration basin ")
        XCTAssertEqual(learned.suggestions(after: "aeration "), ["basin"])
        XCTAssertEqual(LearnedWordPairs(defaults: defaults).suggestions(after: "aeration "), ["basin"])
        doc.text = "aeration "; engine.refresh()
        XCTAssertEqual(engine.candidates, ["basin", "system", "tank"])
    }
    func testAcceptedCompletionAndPredictionLearn() {
        type("aeration ta")
        XCTAssertTrue(engine.accept("tank"))
        XCTAssertEqual(learned.suggestions(after: "aeration "), ["tank"])
        type("aeration ")
        XCTAssertTrue(engine.accept("system"))
        XCTAssertTrue(learned.suggestions(after: "aeration ").contains("system"))
    }
    func testRefreshDoesNotIngestDocumentOrPartialExistingWords() {
        doc.text = "private existing "; engine.refresh(); type("new ")
        XCTAssertEqual(learned.count, 0)
        doc.text = "existing par"; engine.refresh(); type("tial next ")
        XCTAssertEqual(learned.count, 0)
    }
    func testCursorChangesAndSessionResetBreakPairChain() {
        type("aeration "); doc.text = "elsewhere "; engine.refresh(); type("basin ")
        XCTAssertEqual(learned.count, 0)
        engine.resetLearningSession(); type("tank ")
        XCTAssertEqual(learned.count, 0)
    }
    func testSentencesNewlinesAndBackspaceBreakChain() {
        type("aeration. basin\nwater ")
        XCTAssertEqual(learned.count, 0)
        type("ta"); engine.backspace(); type("nk next ")
        XCTAssertEqual(learned.count, 0)
    }
    func testDisabledUnavailableSelectedAndMidDocumentDoNotLearn() {
        settings.wordLearningEnabled = false; type("aeration basin ")
        XCTAssertEqual(learned.count, 0)
        settings.wordLearningEnabled = true; doc.contextAvailable = false; type("water tank ")
        XCTAssertEqual(learned.count, 0)
        doc.contextAvailable = true; doc.after = "rest"; type("water tank ")
        XCTAssertEqual(learned.count, 0)
        doc.after = ""; doc.selection = "selected"; engine.type("replacement ")
        XCTAssertEqual(learned.count, 0)
    }
    func testNumbersEmailAndLongTokensDoNotBecomeLearnedWords() {
        type("123 tank user@example.com water " + String(repeating: "a", count: 49) + " basin ")
        XCTAssertEqual(learned.count, 0)
    }
    func testFrequencyDeduplicationCapacityAndClear() {
        let small = LearnedWordPairs(defaults: defaults, capacity: 2)
        small.record(previous: "water", word: "tank")
        small.record(previous: "WATER", word: "TANK")
        small.record(previous: "water", word: "basin")
        XCTAssertEqual(small.suggestions(after: "water "), ["tank", "basin"])
        small.record(previous: "water", word: "flow")
        XCTAssertEqual(small.count, 2)
        XCTAssertEqual(small.suggestions(after: "water "), ["flow", "basin"])
        small.removeAll()
        XCTAssertEqual(LearnedWordPairs(defaults: defaults).count, 0)
    }
    func testLearningSwitchPersistsAndKeepsExistingHistory() {
        learned.record(previous: "water", word: "tank")
        settings.wordLearningEnabled = false
        XCTAssertFalse(KeyboardSettings(defaults: defaults).wordLearningEnabled)
        XCTAssertEqual(learned.suggestions(after: "water "), ["tank"])
    }
    func testPunctuationLayoutPolicy() {
        for text in [".", ",", "?", "!", ";", ":", "\n"] {
            XCTAssertTrue(KeyboardLayoutPolicy.returnsToLetters(after: text))
        }
        for text in ["'", "-", "/", "1", "(", " "] {
            XCTAssertFalse(KeyboardLayoutPolicy.returnsToLetters(after: text))
        }
    }
}
