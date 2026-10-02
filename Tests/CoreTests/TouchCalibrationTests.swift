import XCTest
@testable import JBoardCore

final class TouchCalibrationTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!
    var model: TouchCalibration!
    var settings: KeyboardSettings!
    var doc: MockDocument!
    var engine: InputController!
    override func setUp() {
        suite = "Calibration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        model = TouchCalibration(defaults: defaults)
        settings = KeyboardSettings(defaults: defaults)
        settings.touchCalibrationEnabled = true
        doc = MockDocument()
        engine = InputController(document: doc, candidates: CandidateService(lexicons:
            [FrequencyLexicon(entries: ["water": 10000])]), settings: settings, touchCalibration: model)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func touches(_ word: String = "wster", offset: Double = 0.05) -> [LetterTouch] {
        word.map { LetterTouch(letter: String($0), boundaries:
            $0 == "s" || $0 == "a" ? [BoundaryTouch(left: "a", right: "s", offset: offset)] : []) }
    }
    func type(_ word: String = "wster") {
        for (letter, touch) in zip(word, touches(word)) { engine.type(String(letter), touch: touch) }
    }
    func testFiveConfirmationsBeforeGradualMovement() {
        for _ in 0..<4 { XCTAssertTrue(model.learn(typed: "wster", corrected: "water", touches: touches())) }
        XCTAssertEqual(model.adjustment(left: "a", right: "s"), 0)
        model.learn(typed: "wster", corrected: "water", touches: touches())
        XCTAssertEqual(model.adjustment(left: "a", right: "s"), 0.005, accuracy: 0.00001)
        for _ in 0..<15 { model.learn(typed: "wster", corrected: "water", touches: touches()) }
        XCTAssertEqual(model.adjustment(left: "a", right: "s"), 0.08, accuracy: 0.00001)
    }
    func testPersistenceResetAndNoStoredWordsOrTouches() {
        for _ in 0..<20 { model.learn(typed: "wster", corrected: "water", touches: touches()) }
        XCTAssertEqual(TouchCalibration(defaults: defaults).adjustment(left: "a", right: "s"), 0.08, accuracy: 0.00001)
        let saved = String(data: defaults.data(forKey: "portraitTouchCalibration.v1")!, encoding: .utf8)!
        XCTAssertFalse(saved.contains("wster")); XCTAssertFalse(saved.contains("water")); XCTAssertFalse(saved.contains("offset"))
        model.reset()
        XCTAssertEqual(TouchCalibration(defaults: defaults).correctionCount, 0)
    }
    func testRejectAmbiguousAndDistantCorrections() {
        for corrected in ["wster", "waters", "watr", "waste", "wts er", "wéter", "wzter"] {
            XCTAssertFalse(model.learn(typed: "wster", corrected: corrected, touches: touches()), corrected)
        }
        XCTAssertFalse(model.learn(typed: "wster", corrected: "water", touches: touches(offset: 0.3)))
        XCTAssertFalse(model.learn(typed: "wster", corrected: "water", touches: touches(offset: .nan)))
        XCTAssertFalse(model.learn(typed: "wster", corrected: "water", touches: []))
        XCTAssertFalse(model.learn(typed: "wster", corrected: "water", touches: touches("water")))
        XCTAssertEqual(model.correctionCount, 0)
    }
    func testBoundedCombinedTargetsAndOppositeEvidence() {
        for _ in 0..<100 { model.learn(typed: "wster", corrected: "water", touches: touches(offset: 0.18)) }
        XCTAssertLessThanOrEqual(model.adjustment(left: "a", right: "s"), 0.12)
        let before = model.adjustment(left: "a", right: "s")
        model.learn(typed: "water", corrected: "wster", touches: touches("water", offset: -0.1))
        XCTAssertLessThan(model.adjustment(left: "a", right: "s"), before)
        XCTAssertEqual(KeyTargeting.boundary(leftEdge: 35, rightEdge: 40, leftWidth: 35, rightWidth: 35,
            leftWeight: 1, rightWeight: 0, calibration: 0.12), 43.8, accuracy: 0.00001)
        XCTAssertEqual(KeyTargeting.boundary(leftEdge: 35, rightEdge: 40, leftWidth: 35, rightWidth: 35,
            leftWeight: 0, rightWeight: 1, calibration: -0.12), 31.2, accuracy: 0.00001)
    }
    func testChosenCorrectionTrainsButTypingAloneDoesNot() {
        type(); XCTAssertEqual(model.correctionCount, 0)
        XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 1)
        XCTAssertEqual(doc.text, "water ")
        XCTAssertFalse(engine.accept("water")); XCTAssertEqual(model.correctionCount, 1)
    }
    func testMissingTouchBackspaceAndExistingPrefixPreventTraining() {
        engine.type("w"); type("ster")
        XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
        doc.text = ""; engine.refresh(); type(); engine.backspace(); engine.type("r", touch: touches("r")[0])
        XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
        doc.text = "w"; engine.refresh(); type("ster")
        XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
    }
    func testCursorChangeAndLifecycleClearPendingEvidence() {
        type(); doc.text = "elsewhere wster"; engine.refresh()
        XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
        doc.text = ""; engine.refresh(); type(); engine.resetTouchCalibrationSession()
        XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
    }
    func testSettingPersistsAndIsIndependentOfWordLearning() {
        settings.touchCalibrationEnabled = false
        XCTAssertFalse(KeyboardSettings(defaults: defaults).touchCalibrationEnabled)
        type(); XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
        settings.touchCalibrationEnabled = true; settings.wordLearningEnabled = false
        doc.text = ""; engine.refresh(); type()
        XCTAssertTrue(engine.accept("water")); XCTAssertEqual(model.correctionCount, 1)
    }
    func testUnavailableContextAndStaleCandidatesDoNotTrain() {
        type(); doc.contextAvailable = false
        XCTAssertFalse(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
        doc.contextAvailable = true; doc.text = ""; engine.refresh(); type(); doc.selection = "wster"
        XCTAssertFalse(engine.accept("water")); XCTAssertEqual(model.correctionCount, 0)
    }
}
