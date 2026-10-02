import XCTest
@testable import JBoardCore

final class SuggestionRemovalTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!
    override func setUp() {
        suite = "RemovalTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testHiddenWordsPersistAndNormalize() {
        let hidden = SuggestionExclusions(defaults: defaults)
        hidden.hide("DON’T")
        XCTAssertTrue(hidden.contains("don't"))
        XCTAssertTrue(SuggestionExclusions(defaults: defaults).contains("Don’t"))
        hidden.removeAll()
        XCTAssertFalse(SuggestionExclusions(defaults: defaults).contains("don't"))
    }
    func testBuiltInAndPersonalCompletionsAreFilteredBeforeRanking() {
        let hidden = SuggestionExclusions(defaults: defaults)
        let personal = PersonalDictionary(defaults: defaults); personal.add("help")
        let service = CandidateService(lexicons: [personal, FrequencyLexicon(entries:
            ["help": 500, "hello": 400, "held": 300, "helm": 200])], exclusions: hidden)
        hidden.hide("HELP")
        XCTAssertFalse(service.candidates(for: "hel").contains("help"))
        XCTAssertEqual(service.candidates(for: "hel").count, 3)
        hidden.hide("hel")
        XCTAssertEqual(service.candidates(for: "hel").count, 3)
        XCTAssertFalse(service.candidates(for: "hel").contains("hel"))
    }
    func testRemoveLearnedAndSavedWordAndPreventRelearning() {
        let hidden = SuggestionExclusions(defaults: defaults)
        let learned = LearnedWordPairs(defaults: defaults, exclusions: hidden)
        let personal = PersonalDictionary(defaults: defaults)
        learned.record(previous: "water", word: "tannk")
        learned.record(previous: "tannk", word: "level")
        personal.add("Tannk")
        hidden.hide("tannk"); learned.remove("TANNK"); personal.remove("tannk")
        XCTAssertEqual(learned.count, 0); XCTAssertTrue(personal.words.isEmpty)
        XCTAssertEqual(LearnedWordPairs(defaults: defaults).count, 0)
        learned.record(previous: "water", word: "tannk")
        learned.record(previous: "tannk", word: "level")
        XCTAssertEqual(learned.count, 0)
        hidden.removeAll(); learned.record(previous: "water", word: "tannk")
        XCTAssertEqual(learned.count, 1)
    }
    func testNextWordsHiddenFromBothSourcesAndRestored() {
        let hidden = SuggestionExclusions(defaults: defaults)
        let learned = LearnedWordPairs(defaults: defaults, exclusions: hidden)
        learned.record(previous: "water", word: "tank")
        let service = CandidateService(lexicons: [], nextWords:
            WordPairPredictor(pairs: ["water": ["tank", "level", "flow"]]), learnedPairs: learned, exclusions: hidden)
        hidden.hide("tank"); learned.remove("tank")
        XCTAssertEqual(service.nextWordCandidates(after: "water "), ["level", "flow"])
        hidden.removeAll()
        XCTAssertEqual(service.nextWordCandidates(after: "water ").first, "tank")
    }
    func testRemovingSuggestionDoesNotChangeDocumentAndInvalidatesOldCandidate() {
        let hidden = SuggestionExclusions(defaults: defaults)
        let doc = MockDocument(); doc.text = "water "
        let engine = InputController(document: doc, candidates: CandidateService(lexicons: [], nextWords:
            WordPairPredictor(pairs: ["water": ["tank"]]), exclusions: hidden), settings: KeyboardSettings(defaults: defaults))
        engine.refresh(); hidden.hide("tank"); engine.refresh()
        XCTAssertFalse(engine.accept("tank"))
        XCTAssertEqual(doc.text, "water ")
        engine.type("tank")
        XCTAssertEqual(doc.text, "water tank")
    }
}
