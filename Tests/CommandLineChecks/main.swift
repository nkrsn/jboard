// Runs the same core test methods when Command Line Tools lack XCTest.
import Foundation

class XCTestCase {
    func setUp() {}
    func tearDown() {}
}
var failures = 0
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line): expected true") }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(!value, file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs != rhs { failures += 1; print("FAIL \(file):\(line): \(lhs) != \(rhs)") }
}
let tests = InputControllerTests()
let cases: [(String, () -> Void)] = [
    ("candidate trailing space", tests.testCandidateAddsSpaceAtEndAndTypingContinues),
    ("candidate existing separators", tests.testCandidateDoesNotAddSpaceBeforeExistingSeparators),
    ("literal candidate trailing space", tests.testLiteralCandidateAlsoCompletesWithSpace),
    ("key preview preference", tests.testKeyPreviewPreferencePersists),
    ("backspace hold threshold", tests.testBackspaceGuardRejectsQuickTapsAndFiresOnlyOnce),
    ("backspace cancellation", tests.testBackspaceCancellationAndNewPressResetDeadline),
    ("backspace settings", tests.testBackspaceSettingsDefaultsPersistenceAndBounds),
    ("tap typing", tests.testTapShiftSpaceReturnAndBackspace),
    ("caps lock", tests.testCapsLockAndPunctuationDoNotConsumeOneShotShift),
    ("candidate replacement", tests.testCandidatesReplaceOnlyWordAndPreserveSurroundings),
    ("stale context", tests.testStaleCandidateDoesNotDeleteNewContext),
    ("suffix and selection changes", tests.testChangedSuffixAndSelectionsPreventReplacement),
    ("nil trailing context", tests.testNilTrailingContextStillAllowsEndOfDocumentCandidates),
    ("unavailable context", tests.testUnavailableContextAndMiddleOfWordSuppressCandidates),
    ("settings", tests.testSettingsPersistAndDisableCandidates),
    ("personal dictionary", tests.testExplicitDictionaryPersistenceDeduplicationAndClear),
    ("Unicode and case", tests.testUnicodeReplacementAndCaseRanking),
    ("no automatic learning or swipe", tests.testNoAutomaticLearningOrSwipeResults)
]
for (name, run) in cases {
    let prior = failures
    tests.setUp(); run(); tests.tearDown()
    print("\(failures == prior ? "PASS" : "FAIL"): \(name)")
}
print("\(cases.count) cases, \(failures) failed assertions")
exit(failures == 0 ? 0 : 1)
