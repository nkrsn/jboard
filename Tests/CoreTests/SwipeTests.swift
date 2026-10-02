import XCTest
@testable import JBoardCore

final class SwipeTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!
    var doc: MockDocument!
    var settings: KeyboardSettings!
    var engine: InputController!
    override func setUp() {
        suite = "SwipeTests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
        doc = MockDocument(); settings = KeyboardSettings(defaults: defaults)
        engine = InputController(document: doc, candidates: CandidateService(lexicons: []), settings: settings)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    var keys: [SwipeKey] {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        return rows.enumerated().flatMap { y, row in row.enumerated().map { x, letter in
            SwipeKey(letter: String(letter), x: y == 0 ? Double(x) + 0.5 : (Double(x) + (y == 2 ? 1.5 : 0.5)) * 10 / 9,
                y: Double(y) * 1.4)
        } }
    }
    func path(_ word: String, noise: Double = 0) -> [SwipeSample] {
        let points = word.compactMap { c in keys.first { $0.letter == String(c) } }
        var samples: [SwipeSample] = []
        for (a, b) in zip(points, points.dropFirst()) {
            for step in 0..<5 {
                let fraction = Double(step) / 5
                samples.append(SwipeSample(x: a.x + (b.x - a.x) * fraction + noise,
                    y: a.y + (b.y - a.y) * fraction - noise, time: Double(samples.count) * 0.015))
            }
        }
        if let last = points.last { samples.append(SwipeSample(x: last.x + noise, y: last.y - noise, time: Double(samples.count) * 0.015)) }
        return samples
    }
    func testDecoderRecognizesRepresentativeWordPaths() {
        let decoder = LocalSwipeDecoder(words: BundledLexicon().swipeWords)
        for word in ["hello", "water", "working", "keyboard", "tomorrow", "thank", "nitrification"] {
            let start = ProcessInfo.processInfo.systemUptime
            let result = decoder.decode(samples: path(word, noise: 0.08), keys: keys)
            print("Swipe \(word): \(result), \((ProcessInfo.processInfo.systemUptime - start) * 1000) ms")
            XCTAssertEqual(result.first, word)
        }
    }
    func testPersonalWordAndTwoPointSwipe() {
        let decoder = LocalSwipeDecoder(words: [SwipeWord(word: "to", frequency: 100)])
        let samples = path("to")
        XCTAssertEqual(decoder.decode(samples: [samples.first!, samples.last!], keys: keys), ["to"])
        XCTAssertEqual(decoder.decode(samples: path("casey"), keys: keys, personal: ["Casey"]).first, "casey")
    }
    func testInvalidAndStationaryPathsRejected() {
        let decoder = LocalSwipeDecoder(words: [SwipeWord(word: "hello", frequency: 100)])
        XCTAssertTrue(decoder.decode(samples: [], keys: keys).isEmpty)
        XCTAssertTrue(decoder.decode(samples: [SwipeSample(x: 1, y: 1, time: 0), SwipeSample(x: 1, y: 1, time: 1)], keys: keys).isEmpty)
        XCTAssertTrue(decoder.decode(samples: path("hello"), keys: []).isEmpty)
        XCTAssertTrue(decoder.decode(samples: [SwipeSample(x: .nan, y: 0, time: 0), SwipeSample(x: 1, y: 2, time: 1)], keys: keys).isEmpty)
        XCTAssertTrue(decoder.decode(samples: [SwipeSample(x: 100, y: 100, time: 0), SwipeSample(x: 102, y: 102, time: 1)], keys: keys).isEmpty)
    }
    func testInsertionAlternativesAndWholeWordUndo() {
        doc.text = "I am "; engine.refresh()
        XCTAssertTrue(engine.insertSwipe(["working", "walking"]))
        XCTAssertEqual(doc.text, "I am working ")
        XCTAssertEqual(engine.candidates, ["working", "walking"])
        engine.refresh(); XCTAssertEqual(engine.candidates, ["working", "walking"])
        XCTAssertTrue(engine.accept("walking")); XCTAssertEqual(doc.text, "I am walking ")
        engine.backspace(); XCTAssertEqual(doc.text, "I am ")
    }
    func testConsecutiveSwipesAndPunctuationSpacing() {
        XCTAssertTrue(engine.insertSwipe(["hello"]))
        XCTAssertTrue(engine.insertSwipe(["world"]))
        XCTAssertEqual(doc.text, "hello world ")
        engine.type("."); XCTAssertEqual(doc.text, "hello world.")
        engine.backspace(); XCTAssertEqual(doc.text, "hello world")
    }
    func testTapAfterSwipeEndsWholeWordUndoAndSpaceDoesNotDuplicate() {
        engine.insertSwipe(["hello"]); engine.type(" ")
        XCTAssertEqual(doc.text, "hello ")
        engine.type("a"); engine.backspace(); XCTAssertEqual(doc.text, "hello ")
        engine.backspace(); XCTAssertEqual(doc.text, "hello")
    }
    func testStaleAlternativeCannotReplaceMovedText() {
        engine.insertSwipe(["hello", "help"]); doc.text = "elsewhere "
        XCTAssertFalse(engine.accept("help")); XCTAssertEqual(doc.text, "elsewhere ")
    }
    func testUnavailableSelectedAndPartialWordRejectSwipe() {
        doc.contextAvailable = false; XCTAssertFalse(engine.insertSwipe(["hello"]))
        doc.contextAvailable = true; doc.selection = "selected"; XCTAssertFalse(engine.insertSwipe(["hello"]))
        doc.selection = nil; doc.text = "123"; XCTAssertFalse(engine.insertSwipe(["hello"]))
        doc.text = "hel"; XCTAssertFalse(engine.insertSwipe(["hello"]))
        doc.text = ""; doc.after = "lo"; XCTAssertFalse(engine.insertSwipe(["hello"]))
        doc.after = ""; settings.swipeEnabled = false; XCTAssertFalse(engine.insertSwipe(["hello"]))
    }
    func testShiftAndExistingPunctuation() {
        engine.toggleShift(); engine.insertSwipe(["hello", "help"])
        XCTAssertEqual(doc.text, "Hello "); XCTAssertEqual(engine.shift, .off)
        XCTAssertTrue(engine.accept("Help")); XCTAssertEqual(doc.text, "Help ")
        doc.text = ""; doc.after = "!"; engine.refresh(); engine.lockShift()
        engine.insertSwipe(["hello"]); XCTAssertEqual(doc.text, "HELLO"); XCTAssertEqual(doc.after, "!")
    }
    func testHiddenWordAndSuggestionSetting() {
        let hidden = SuggestionExclusions(defaults: defaults); hidden.hide("hello")
        engine = InputController(document: doc, candidates: CandidateService(lexicons: [], exclusions: hidden), settings: settings)
        XCTAssertTrue(engine.insertSwipe(["hello", "help"]))
        XCTAssertEqual(doc.text, "help ")
        settings.candidatesEnabled = false; engine.refresh(); XCTAssertTrue(engine.candidates.isEmpty)
        engine.backspace(); XCTAssertEqual(doc.text, "")
    }
    func testAutomaticSwipeResultsDoNotTrainPersonalHistory() {
        let learned = LearnedWordPairs(defaults: defaults)
        engine = InputController(document: doc, candidates: CandidateService(lexicons: [], learnedPairs: learned), settings: settings, learnedPairs: learned)
        engine.type("water "); engine.insertSwipe(["tank", "task"]); engine.accept("task")
        XCTAssertEqual(learned.count, 0)
    }
}
