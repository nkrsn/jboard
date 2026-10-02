import XCTest
@testable import JBoardCore

final class CursorControlTests: XCTestCase {
    func testMotionDeadZoneAndFractionalTravel() {
        var motion = CursorMotion()
        XCTAssertEqual(motion.consume(dx: 4, dy: 0).characters, 0)
        XCTAssertEqual(motion.consume(dx: 5, dy: 0).characters, 1)
        XCTAssertEqual(motion.consume(dx: -18, dy: 0).characters, -2)
        XCTAssertEqual(motion.consume(dx: 0, dy: -27).lines, 0)
        XCTAssertEqual(motion.consume(dx: 0, dy: -1).lines, -1)
        motion.reset(); XCTAssertEqual(motion.consume(dx: 1, dy: 0).characters, 0)
    }
    func testVerticalDominanceRejectsSideDriftAndBoundsLargeMoves() {
        var motion = CursorMotion()
        let vertical = motion.consume(dx: 10, dy: 30)
        XCTAssertEqual(vertical.characters, 0); XCTAssertEqual(vertical.lines, 1)
        XCTAssertEqual(motion.consume(dx: 0, dy: 0).characters, 0)
        motion.reset(); XCTAssertEqual(motion.consume(dx: 1000000, dy: 0).characters, 12)
        motion.reset(); XCTAssertEqual(motion.consume(dx: .nan, dy: 0).characters, 0)
    }
    func testHorizontalOffsetsPreserveEmojiAndComposedCharacters() {
        var navigator = CursorNavigator()
        XCTAssertEqual(navigator.horizontalOffset(-1, before: "a👩🏼‍🏫", after: ""), -"👩🏼‍🏫".utf16.count)
        XCTAssertEqual(navigator.horizontalOffset(1, before: "", after: "e\u{301}z"), 2)
        XCTAssertEqual(navigator.horizontalOffset(-5, before: "ab", after: ""), -2)
        XCTAssertEqual(navigator.horizontalOffset(5, before: "ab", after: ""), 0)
    }
    func testUpAndDownKeepColumnAcrossShortLine() {
        var navigator = CursorNavigator()
        let doc = MockDocument(); doc.text = "abcde"; doc.after = "f\nx\nabcdef"
        var offset = navigator.verticalOffset(1, before: doc.text, after: doc.after)
        doc.moveCursor(byUTF16Offset: offset)
        XCTAssertEqual(doc.text, "abcdef\nx")
        offset = navigator.verticalOffset(1, before: doc.text, after: doc.after)
        doc.moveCursor(byUTF16Offset: offset)
        XCTAssertEqual(doc.text, "abcdef\nx\nabcde")
        offset = navigator.verticalOffset(-2, before: doc.text, after: doc.after)
        doc.moveCursor(byUTF16Offset: offset)
        XCTAssertEqual(doc.text, "abcde")
    }
    func testExplicitNewlinesOnlyAndEmptyLineBoundaries() {
        var navigator = CursorNavigator()
        XCTAssertEqual(navigator.verticalOffset(-1, before: "a long wrapped paragraph", after: "more text"), 0)
        XCTAssertEqual(navigator.verticalOffset(1, before: "a long wrapped paragraph", after: "more text"), 0)
        let doc = MockDocument(); doc.text = "ab"; doc.after = "\n\ncd"
        doc.moveCursor(byUTF16Offset: navigator.verticalOffset(1, before: doc.text, after: doc.after))
        XCTAssertEqual(doc.text, "ab\n")
        doc.moveCursor(byUTF16Offset: navigator.verticalOffset(1, before: doc.text, after: doc.after))
        XCTAssertEqual(doc.text, "ab\n\ncd")
        XCTAssertEqual(navigator.verticalOffset(1, before: doc.text, after: doc.after), 0)
    }
    func testVerticalUnicodeOffsetsAndCRLF() {
        var navigator = CursorNavigator()
        let doc = MockDocument(); doc.text = "😀x\n👩🏼‍🏫"; doc.after = "z"
        doc.moveCursor(byUTF16Offset: navigator.verticalOffset(-1, before: doc.text, after: doc.after))
        XCTAssertEqual(doc.text, "😀")
        navigator.reset(); doc.text = "ab\r\nc"; doc.after = "d"
        doc.moveCursor(byUTF16Offset: navigator.verticalOffset(-1, before: doc.text, after: doc.after))
        XCTAssertEqual(doc.text, "a")
    }
    func testHorizontalMoveResetsPreferredColumn() {
        var navigator = CursorNavigator()
        let doc = MockDocument(); doc.text = "abcde"; doc.after = "f\nxy\nabcdef"
        doc.moveCursor(byUTF16Offset: navigator.verticalOffset(1, before: doc.text, after: doc.after))
        doc.moveCursor(byUTF16Offset: navigator.horizontalOffset(-1, before: doc.text, after: doc.after))
        doc.moveCursor(byUTF16Offset: navigator.verticalOffset(1, before: doc.text, after: doc.after))
        XCTAssertEqual(doc.text, "abcdef\nxy\na")
    }
    func testEngineCursorControlClearsSwipeUndoAndPreservesText() {
        let suite = "CursorTests.\(UUID().uuidString)", doc = MockDocument()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KeyboardSettings(defaults: defaults)
        let engine = InputController(document: doc, candidates: CandidateService(lexicons: []), settings: settings)
        engine.insertSwipe(["hello", "help"]); engine.beginCursorControl()
        engine.moveCursor(characters: -2, lines: 0)
        XCTAssertEqual(doc.text, "hell"); XCTAssertEqual(doc.after, "o ")
        XCTAssertFalse(engine.accept("help")); XCTAssertEqual(doc.text + doc.after, "hello ")
        engine.backspace(); XCTAssertEqual(doc.text, "hel")
    }
    func testUnavailableContextAndSelectionDoNotMove() {
        let suite = "CursorUnavailable.\(UUID().uuidString)", doc = MockDocument()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = InputController(document: doc, candidates: CandidateService(lexicons: []), settings: KeyboardSettings(defaults: defaults))
        doc.text = "hello"; doc.selection = "hello"; engine.moveCursor(characters: -1, lines: 0)
        XCTAssertEqual(doc.text, "hello")
        doc.selection = nil; doc.contextAvailable = false; engine.moveCursor(characters: -1, lines: 0)
        XCTAssertEqual(doc.text, "hello")
    }
    func testCursorSettingPersists() {
        let suite = "CursorSetting.\(UUID().uuidString)"
        let actual = UserDefaults(suiteName: suite)!
        defer { actual.removePersistentDomain(forName: suite) }
        let settings = KeyboardSettings(defaults: actual)
        XCTAssertTrue(settings.cursorPadEnabled); settings.cursorPadEnabled = false
        XCTAssertFalse(KeyboardSettings(defaults: actual).cursorPadEnabled)
    }
}
