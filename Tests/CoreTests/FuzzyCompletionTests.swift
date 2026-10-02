import XCTest
@testable import JBoardCore

final class FuzzyCompletionTests: XCTestCase {
    func testMistypedPrefixContinuesIntoLongerWord() {
        let service = CandidateService(lexicons: [FrequencyLexicon(entries: ["work": 5000, "working": 3000])])
        for input in ["woeki", "wroki", "workki", "wrki"] {
            XCTAssertTrue(service.candidates(for: input).contains("working"), input)
        }
        XCTAssertTrue(service.candidates(for: "woek").contains("work"))
        XCTAssertEqual(service.candidates(for: "WOEKI"), ["WOEKI", "WORKING"])
    }
    func testRealDictionaryExamples() {
        let service = CandidateService(lexicons: [BundledLexicon()])
        for (input, expected) in [("woek", "work"), ("woeki", "working"), ("woekin", "working"), ("woeking", "working"), ("nitrifuc", "nitrification")] {
            let result = service.candidates(for: input)
            print("Fuzzy completion: \(input) → \(result)")
            XCTAssertTrue(result.contains(expected), "\(input): \(result)")
            XCTAssertEqual(result.first, input)
        }
    }
    func testNoTwoEditExpansionOrKnownWordCorrection() {
        let service = CandidateService(lexicons: [FrequencyLexicon(entries: ["working": 3000, "form": 5, "formal": 100, "fromage": 500])])
        XCTAssertEqual(service.candidates(for: "wxqki"), ["wxqki"])
        XCTAssertEqual(service.candidates(for: "form"), ["form", "formal"])
    }
    func testFuzzySuggestionsDoNotBiasTouchTargetsOrBypassHiding() {
        let suite = "FuzzyCompletion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hidden = SuggestionExclusions(defaults: defaults)
        let service = CandidateService(lexicons: [FrequencyLexicon(entries: ["working": 3000])], exclusions: hidden)
        XCTAssertTrue(service.nextLetterWeights(for: "woeki").isEmpty)
        hidden.hide("working")
        XCTAssertEqual(service.candidates(for: "woeki"), ["woeki"])
    }
    func testAcceptReplacesWholeMistypedPrefixAndAddsSpace() {
        let suite = "FuzzyAccept.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let doc = MockDocument(); doc.text = "I am woeki"
        let engine = InputController(document: doc, candidates: CandidateService(lexicons:
            [FrequencyLexicon(entries: ["working": 3000])]), settings: KeyboardSettings(defaults: defaults))
        engine.refresh(); XCTAssertTrue(engine.accept("working"))
        XCTAssertEqual(doc.text, "I am working ")
    }
    func testUncachedPrefixLookupTiming() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let lexicon = try FrequencyLexicon(contentsOf: root.appendingPathComponent("Core/Resources/english-frequency.txt"))
        let inputs = ["workign", "wrokin", "woeki", "woekin", "wprki", "workiing", "nitrifuc", "denitrifuc", "hellp", "helol", "pleasr", "sometging", "becausr", "tomorroe", "thinkib", "lookib", "watrr", "averagw", "testib", "undrr"]
        var maximum = 0.0
        let start = ProcessInfo.processInfo.systemUptime
        for input in inputs {
            let began = ProcessInfo.processInfo.systemUptime
            _ = lexicon.matches(for: input)
            maximum = max(maximum, ProcessInfo.processInfo.systemUptime - began)
        }
        let average = (ProcessInfo.processInfo.systemUptime - start) / Double(inputs.count)
        print("Uncached typo-prefix lookup on Mac debug: average \(average * 1000) ms, max \(maximum * 1000) ms")
        XCTAssertLessThan(average, 0.02)
    }
}
