import XCTest
@testable import JBoardCore

final class KeyTargetingTests: XCTestCase {
    func testNeutralAndEqualWeightsKeepMidpoint() {
        for weight in [0.0, 0.5, 1.0] {
            XCTAssertEqual(KeyTargeting.boundary(leftEdge: 35, rightEdge: 40, leftWidth: 35,
                rightWidth: 35, leftWeight: weight, rightWeight: weight), 37.5)
        }
    }
    func testPreferenceGrowsLikelySideAndIsBounded() {
        let left = KeyTargeting.boundary(leftEdge: 35, rightEdge: 40, leftWidth: 35,
            rightWidth: 35, leftWeight: 1, rightWeight: 0)
        let right = KeyTargeting.boundary(leftEdge: 35, rightEdge: 40, leftWidth: 35,
            rightWidth: 35, leftWeight: 0, rightWeight: 1)
        XCTAssertEqual(left, 41.7, accuracy: 0.0001)
        XCTAssertEqual(right, 33.3, accuracy: 0.0001)
    }
    func testAllRowCellsStayContiguousAndRetainCenters() {
        // Sweep the strong-preference extremes for all ten-key combinations.
        for mask in 0..<1024 {
            var boundaries = [0.0]
            for index in 0..<9 {
                boundaries.append(KeyTargeting.boundary(leftEdge: Double(index * 40 + 35),
                    rightEdge: Double((index + 1) * 40), leftWidth: 35, rightWidth: 35,
                    leftWeight: mask & (1 << index) == 0 ? 0 : 1,
                    rightWeight: mask & (1 << (index + 1)) == 0 ? 0 : 1))
            }
            boundaries.append(395)
            for index in 0..<10 {
                let center = Double(index * 40) + 17.5
                XCTAssertLessThan(boundaries[index], center)
                XCTAssertGreaterThan(boundaries[index + 1], center)
                XCTAssertGreaterThan(boundaries[index + 1] - boundaries[index], 26)
            }
        }
    }
    func testInvalidWeightsAndWidthsStaySafe() {
        XCTAssertEqual(KeyTargeting.boundary(leftEdge: 35, rightEdge: 40, leftWidth: 35,
            rightWidth: 35, leftWeight: .nan, rightWeight: .infinity), 37.5)
        XCTAssertEqual(KeyTargeting.boundary(leftEdge: 35, rightEdge: 40, leftWidth: 0,
            rightWidth: 35, leftWeight: 1, rightWeight: 0), 37.5)
    }
    func testDictionaryHintsUseOnlyRealPrefixContinuations() {
        let service = CandidateService(lexicons: [FrequencyLexicon(entries:
            ["the": 10000, "there": 1000, "this": 100, "to": 1])])
        let hints = service.nextLetterWeights(for: "TH")
        XCTAssertEqual(hints["e"], 1)
        XCTAssertLessThan(hints["i"] ?? 1, 1)
        XCTAssertNil(hints["t"])
        for prefix in ["", "zzzz", "teh", "123", "é"] {
            XCTAssertTrue(service.nextLetterWeights(for: prefix).isEmpty, prefix)
        }
    }
    func testHiddenWordsCannotInfluenceTargets() {
        let suite = "TargetHidden.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hidden = SuggestionExclusions(defaults: defaults)
        hidden.hide("the")
        let service = CandidateService(lexicons: [FrequencyLexicon(entries: ["the": 10000, "this": 100])], exclusions: hidden)
        XCTAssertEqual(service.nextLetterWeights(for: "th"), ["i": 1])
    }
    func testEngineHonorsSettingAndSafeContextIndependentlyOfCandidateBar() {
        let suite = "TargetSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KeyboardSettings(defaults: defaults)
        let doc = MockDocument(); doc.text = "th"
        let engine = InputController(document: doc, candidates: CandidateService(lexicons:
            [FrequencyLexicon(entries: ["the": 100])]), settings: settings)
        engine.refresh(); XCTAssertEqual(engine.nextLetterWeights, ["e": 1])
        settings.candidatesEnabled = false; engine.refresh()
        XCTAssertEqual(engine.nextLetterWeights, ["e": 1]); XCTAssertTrue(engine.candidates.isEmpty)
        settings.dynamicKeyTargetsEnabled = false; engine.refresh()
        XCTAssertTrue(engine.nextLetterWeights.isEmpty)
        XCTAssertFalse(KeyboardSettings(defaults: defaults).dynamicKeyTargetsEnabled)
        settings.dynamicKeyTargetsEnabled = true
        doc.after = "e"; engine.refresh(); XCTAssertTrue(engine.nextLetterWeights.isEmpty)
        doc.after = ""; doc.selection = "th"; engine.refresh(); XCTAssertTrue(engine.nextLetterWeights.isEmpty)
        doc.selection = nil; doc.contextAvailable = false; engine.refresh(); XCTAssertTrue(engine.nextLetterWeights.isEmpty)
        doc.contextAvailable = true; doc.text = "the "; engine.refresh(); XCTAssertTrue(engine.nextLetterWeights.isEmpty)
    }
    func testPackagedHintsRemainFastEnoughForTyping() {
        let service = CandidateService(lexicons: [BundledLexicon()])
        _ = service.nextLetterWeights(for: "th")
        let start = Date()
        for _ in 0..<50 {
            for word in ["t", "th", "the", "nitrific", "zzzz"] {
                let hints = service.nextLetterWeights(for: word)
                XCTAssertTrue(hints.values.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 1 })
            }
        }
        let average = Date().timeIntervalSince(start) / 250
        print("Average dynamic target lookup on Mac debug: \(average * 1000) ms")
        XCTAssertLessThan(average, 0.02)
    }
}
