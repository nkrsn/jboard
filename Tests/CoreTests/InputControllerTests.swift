import Foundation
#if !JBOARD_STANDALONE_CHECKS
import XCTest
@testable import JBoardCore
#endif

final class MockDocument: TextDocument {
    var text = ""
    var after = ""
    var selection: String?
    var contextAvailable = true
    var trailingContextAvailable = true
    var beforeInput: String? { contextAvailable ? text : nil }
    var afterInput: String? { contextAvailable && trailingContextAvailable ? after : nil }
    func insertText(_ input: String) { text += input; selection = nil }
    func moveCursor(byUTF16Offset offset: Int) {
        let combined = text + after
        let position = min(combined.utf16.count, max(0, text.utf16.count + offset))
        let index = String.Index(utf16Offset: position, in: combined)
        text = String(combined[..<index]); after = String(combined[index...])
    }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

final class InputControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var doc: MockDocument!
    private var settings: KeyboardSettings!
    private var dictionary: PersonalDictionary!
    private var engine: InputController!
    override func setUp() {
        suite = "JBoardTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        doc = MockDocument(); settings = KeyboardSettings(defaults: defaults)
        dictionary = PersonalDictionary(defaults: defaults)
        engine = InputController(document: doc,
            candidates: CandidateService(lexicons: [FrequencyLexicon(entries: ["hello": 2_000, "help": 3_000]), dictionary]), settings: settings)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testTapShiftSpaceReturnAndBackspace() {
        engine.toggleShift(); engine.type("h"); engine.type("i"); engine.type(" ")
        engine.type("1"); engine.type("\n")
        XCTAssertEqual(doc.text, "Hi 1\n")
        engine.backspace(); XCTAssertEqual(doc.text, "Hi 1")
        XCTAssertEqual(engine.shift, .off)
    }
    func testCapsLockAndPunctuationDoNotConsumeOneShotShift() {
        engine.toggleShift(); engine.type("."); XCTAssertEqual(engine.shift, .once)
        engine.type("a"); engine.lockShift(); engine.type("bc")
        XCTAssertEqual(doc.text, ".ABC"); XCTAssertEqual(engine.shift, .locked)
        engine.toggleShift(); XCTAssertEqual(engine.shift, .off)
    }
    func testCandidatesReplaceOnlyWordAndPreserveSurroundings() {
        doc.text = "Say hel"; doc.after = "!"; engine.refresh()
        XCTAssertEqual(engine.candidates, ["hel", "help", "hello"])
        XCTAssertTrue(engine.accept("hello"))
        XCTAssertEqual(doc.text, "Say hello"); XCTAssertEqual(doc.after, "!")
    }
    func testStaleCandidateDoesNotDeleteNewContext() {
        doc.text = "hel"; engine.refresh(); doc.text = "other"
        XCTAssertFalse(engine.accept("hello")); XCTAssertEqual(doc.text, "other")
    }
    func testChangedSuffixAndSelectionsPreventReplacement() {
        doc.text = "hel"; engine.refresh(); doc.after = "lo"
        XCTAssertFalse(engine.accept("hello")); XCTAssertEqual(doc.text, "hel")
        doc.after = ""; engine.refresh(); doc.selection = "selected"
        XCTAssertFalse(engine.accept("hello")); XCTAssertEqual(doc.text, "hel")
    }
    func testNilTrailingContextStillAllowsEndOfDocumentCandidates() {
        doc.text = "hel"; doc.trailingContextAvailable = false; engine.refresh()
        XCTAssertTrue(engine.accept("hello")); XCTAssertEqual(doc.text, "hello ")
    }
    func testUnavailableContextAndMiddleOfWordSuppressCandidates() {
        doc.text = "hel"; doc.contextAvailable = false; engine.refresh()
        XCTAssertTrue(engine.candidates.isEmpty)
        doc.contextAvailable = true; doc.after = "lo"; engine.refresh()
        XCTAssertTrue(engine.candidates.isEmpty)
        doc.after = ""; doc.selection = "hello"; engine.refresh()
        XCTAssertTrue(engine.candidates.isEmpty)
    }
    func testSettingsPersistAndDisableCandidates() {
        settings.candidatesEnabled = false
        XCTAssertFalse(KeyboardSettings(defaults: defaults).candidatesEnabled)
        doc.text = "hel"; engine.refresh(); XCTAssertTrue(engine.candidates.isEmpty)
    }
    func testExplicitDictionaryPersistenceDeduplicationAndClear() {
        dictionary.add("nitrification"); dictionary.add("Nitrification"); dictionary.add("two words")
        XCTAssertEqual(PersonalDictionary(defaults: defaults).words, ["nitrification"])
        doc.text = "nit"; engine.refresh(); XCTAssertTrue(engine.candidates.contains("nitrification"))
        dictionary.removeAll(); engine.refresh(); XCTAssertEqual(engine.candidates, ["nit"])
    }
    func testUnicodeReplacementAndCaseRanking() {
        dictionary.add("café")
        doc.text = "Say cafe\u{301}"; engine.refresh()
        XCTAssertTrue(engine.accept("cafe\u{301}")); XCTAssertEqual(doc.text, "Say café ")
        doc.text = "HEL"; engine.refresh(); XCTAssertTrue(engine.candidates.contains("HELLO"))
    }
    func testNoAutomaticLearningOrSwipeResults() {
        engine.type("privateword "); XCTAssertTrue(dictionary.words.isEmpty)
        XCTAssertTrue(DisabledSwipeDecoder().decode(samples: [], precedingText: "hello").isEmpty)
    }
    func testBackspaceGuardRejectsQuickTapsAndFiresOnlyOnce() {
        var press = BackspacePress()
        press.begin(at: 10, delay: 0.12)
        XCTAssertFalse(press.consume(at: 10.08))
        XCTAssertTrue(press.consume(at: 10.121))
        XCTAssertFalse(press.consume(at: 11))
    }
    func testBackspaceCancellationAndNewPressResetDeadline() {
        var press = BackspacePress()
        press.begin(at: 10, delay: 0.12)
        press.cancel()
        XCTAssertFalse(press.consume(at: 11))
        press.begin(at: 20, delay: 0.18)
        XCTAssertFalse(press.consume(at: 20.12))
        XCTAssertTrue(press.consume(at: 20.181))
        press.begin(at: 30, delay: 0.08)
        XCTAssertTrue(press.consume(at: 30.081))
    }
    func testBackspaceSettingsDefaultsPersistenceAndBounds() {
        XCTAssertTrue(settings.backspaceGuardEnabled)
        XCTAssertEqual(settings.backspaceDelayMilliseconds, 120)
        settings.backspaceGuardEnabled = false
        settings.backspaceDelayMilliseconds = 160
        let restored = KeyboardSettings(defaults: defaults)
        XCTAssertFalse(restored.backspaceGuardEnabled)
        XCTAssertEqual(restored.backspaceDelayMilliseconds, 160)
        settings.backspaceDelayMilliseconds = 1
        XCTAssertEqual(settings.backspaceDelayMilliseconds, 80)
        settings.backspaceDelayMilliseconds = 1000
        XCTAssertEqual(settings.backspaceDelayMilliseconds, 180)
    }
    func testCandidateAddsSpaceAtEndAndTypingContinues() {
        doc.text = "Say hel"; engine.refresh()
        XCTAssertTrue(engine.accept("hello"))
        XCTAssertEqual(doc.text, "Say hello ")
        XCTAssertTrue(engine.candidates.isEmpty)
        engine.type("world")
        XCTAssertEqual(doc.text, "Say hello world")
    }
    func testCandidateDoesNotAddSpaceBeforeExistingSeparators() {
        for separator in [" ", " next", "!", ",", ".", "\n", "\t", ")"] {
            doc.text = "hel"; doc.after = separator; engine.refresh()
            XCTAssertTrue(engine.accept("hello"))
            XCTAssertEqual(doc.text, "hello")
            XCTAssertEqual(doc.after, separator)
        }
    }
    func testLiteralCandidateAlsoCompletesWithSpace() {
        doc.text = "customword"; engine.refresh()
        XCTAssertTrue(engine.accept("customword"))
        XCTAssertEqual(doc.text, "customword ")
    }
    func testKeyPreviewPreferencePersists() {
        XCTAssertTrue(settings.keyPreviewsEnabled)
        settings.keyPreviewsEnabled = false
        XCTAssertFalse(KeyboardSettings(defaults: defaults).keyPreviewsEnabled)
    }
}
