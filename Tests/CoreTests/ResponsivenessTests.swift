import XCTest
@testable import JBoardCore

final class ResponsivenessTests: XCTestCase {
    func testTinyDriftAllowedButLeavingKeyCancels() {
        XCTAssertTrue(BackspacePress.allowsDrift(horizontalOverflow: 2, verticalOverflow: 5))
        XCTAssertTrue(BackspacePress.allowsDrift(horizontalOverflow: 8, verticalOverflow: 0))
        XCTAssertFalse(BackspacePress.allowsDrift(horizontalOverflow: 8.1, verticalOverflow: 0))
        XCTAssertFalse(BackspacePress.allowsDrift(horizontalOverflow: 0, verticalOverflow: 9))
        XCTAssertFalse(BackspacePress.allowsDrift(horizontalOverflow: .nan, verticalOverflow: 0))
    }
    func testEarlyTimerCanRescheduleWithoutLosingPress() {
        var press = BackspacePress(); press.begin(at: 10, delay: 0.08)
        XCTAssertFalse(press.consume(at: 10.079))
        XCTAssertEqual(press.remainingDelay(at: 10.079)!, 0.001, accuracy: 0.00001)
        XCTAssertTrue(press.consume(at: 10.081))
        XCTAssertNil(press.remainingDelay(at: 10.082))
    }
    func testPhysicalTimestampsHandleDelayedDeliveryAndFreshPress() {
        var press = BackspacePress(); press.begin(at: 10, delay: 0.08)
        // Begin event may be processed late; the 90ms physical release still qualifies.
        XCTAssertTrue(press.consume(at: 10.09))
        press.begin(at: 11, delay: 0.08); press.cancel()
        XCTAssertFalse(press.consume(at: 11.2))
        press.begin(at: 12, delay: 0.08)
        XCTAssertTrue(press.consume(at: 12.081))
    }
    func testUnchangedNotificationsKeepDeleteContextButEditsAndFieldChangesDoNot() {
        let id = UUID()
        let original = DeletionContext(documentID: id, before: "hello", after: "", selection: nil)
        XCTAssertEqual(original, DeletionContext(documentID: id, before: "hello", after: "", selection: nil))
        XCTAssertNotEqual(original, DeletionContext(documentID: UUID(), before: "hello", after: "", selection: nil))
        XCTAssertNotEqual(original, DeletionContext(documentID: id, before: "hell", after: "o", selection: nil))
        XCTAssertNotEqual(original, DeletionContext(documentID: id, before: "hello", after: "", selection: "word"))
        XCTAssertNotEqual(original, DeletionContext(documentID: id, before: nil, after: nil, selection: nil))
    }
    func testCachedLookupsPreserveCorrectionsAndRanking() {
        let lexicon = FrequencyLexicon(entries: ["water": 1000, "waters": 100, "waste": 50])
        for query in ["w", "wa", "wat", "wster"] {
            let first = lexicon.matches(for: query)
            for _ in 0..<5 {
                let cached = lexicon.matches(for: query)
                XCTAssertEqual(cached.map(\.word), first.map(\.word))
                XCTAssertEqual(cached.map(\.frequency), first.map(\.frequency))
                XCTAssertEqual(cached.map(\.editCost), first.map(\.editCost))
            }
        }
        for index in 0..<150 { _ = lexicon.matches(for: "x" + String(index)) }
        XCTAssertTrue(lexicon.matches(for: "wster").contains { $0.word == "water" })
    }
}
