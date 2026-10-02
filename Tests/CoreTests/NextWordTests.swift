import XCTest
@testable import JBoardCore

final class NextWordTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var doc: MockDocument!
    private var settings: KeyboardSettings!
    private var engine: InputController!
    private let predictor = WordPairPredictor(pairs: ["thank": ["you"], "you": ["can", "are", "have"], "can": ["help"]])
    override func setUp() {
        suite = "JBoardNextWords.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        doc = MockDocument(); settings = KeyboardSettings(defaults: defaults)
        engine = InputController(document: doc, candidates: CandidateService(
            lexicons: [FrequencyLexicon(entries: ["thank": 100, "thanks": 50])], nextWords: predictor), settings: settings)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testKnownPairsAndCaseNormalization() {
        XCTAssertEqual(predictor.suggestions(after: "I thank "), ["you"])
        XCTAssertEqual(predictor.suggestions(after: "YOU "), ["can", "are", "have"])
        XCTAssertEqual(predictor.suggestions(after: "thank, "), ["you"])
    }
    func testSentenceLineAndUnknownBoundaries() {
        for text in ["", " ", "thank", "thank. ", "thank! ", "thank? ", "thank\n", "thank\n  ", "unknown "] {
            XCTAssertTrue(predictor.suggestions(after: text).isEmpty, text)
        }
    }
    func testShiftCapitalizesNextWordPredictions() {
        doc.text = "thank "; engine.refresh(); engine.toggleShift()
        XCTAssertEqual(engine.candidates, ["You"])
        XCTAssertTrue(engine.accept("You"))
        XCTAssertEqual(doc.text, "thank You ")
        XCTAssertEqual(engine.shift, .off)
        XCTAssertEqual(engine.candidates, ["can", "are", "have"])
    }
    func testPredictionAppendsWithoutDeletingAndChains() {
        doc.text = "I thank "; engine.refresh()
        XCTAssertEqual(engine.candidates, ["you"])
        XCTAssertTrue(engine.accept("you"))
        XCTAssertEqual(doc.text, "I thank you ")
        XCTAssertEqual(engine.candidates, ["can", "are", "have"])
        XCTAssertTrue(engine.accept("can"))
        XCTAssertEqual(doc.text, "I thank you can ")
    }
    func testCompletionTransitionsToNextWord() {
        doc.text = "tha"; engine.refresh()
        XCTAssertTrue(engine.accept("thank"))
        XCTAssertEqual(doc.text, "thank ")
        XCTAssertEqual(engine.candidates, ["you"])
        engine.type("c")
        XCTAssertEqual(engine.candidates.first, "c")
        XCTAssertFalse(engine.accept("you"))
        XCTAssertEqual(doc.text, "thank c")
    }
    func testStalePredictionAndSelectionAreRejected() {
        doc.text = "thank "; engine.refresh(); doc.text = "something else "
        XCTAssertFalse(engine.accept("you")); XCTAssertEqual(doc.text, "something else ")
        doc.text = "thank "; engine.refresh(); doc.selection = "selected"
        XCTAssertFalse(engine.accept("you")); XCTAssertEqual(doc.text, "thank ")
    }
    func testDisabledAndUnavailableContextSuppressPredictions() {
        doc.text = "thank "; settings.candidatesEnabled = false; engine.refresh()
        XCTAssertTrue(engine.candidates.isEmpty)
        settings.candidatesEnabled = true; doc.contextAvailable = false; engine.refresh()
        XCTAssertTrue(engine.candidates.isEmpty)
        doc.contextAvailable = true; doc.after = "existing"; engine.refresh()
        XCTAssertTrue(engine.candidates.isEmpty)
    }
    func testPackagedWordPairData() {
        let model = WordPairPredictor.bundled
        XCTAssertEqual(model.contextCount, 16_600)
        XCTAssertEqual(model.suggestions(after: "thank ").first, "you")
        XCTAssertEqual(model.suggestions(after: "looking ").first, "for")
        XCTAssertTrue(model.suggestions(after: "you ").contains("can"))
    }
}
