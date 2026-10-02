import XCTest
@testable import JBoardCore

final class DictionaryTests: XCTestCase {
    private func service(_ entries: [String: Int64]) -> CandidateService {
        CandidateService(lexicons: [FrequencyLexicon(entries: entries)])
    }
    func testFrequencyRankingKeepsLiteralFirst() {
        let result = service(["help": 50_000, "hello": 20_000, "helium": 10]).candidates(for: "hel")
        XCTAssertEqual(result, ["hel", "help", "hello"])
    }
    func testMissingExtraWrongAndTransposedLetters() {
        let candidates = service(["hello": 50_000, "help": 80_000, "water": 90_000, "receive": 70_000])
        XCTAssertTrue(candidates.candidates(for: "helo").contains("hello"))
        XCTAssertTrue(candidates.candidates(for: "hellp").contains("help"))
        XCTAssertTrue(candidates.candidates(for: "wster").contains("water"))
        XCTAssertTrue(candidates.candidates(for: "recieve").contains("receive"))
    }
    func testStrongCorrectionBeatsObscureCompletion() {
        XCTAssertEqual(service(["the": 1_000_000, "tehran": 50]).candidates(for: "teh"), ["teh", "the", "tehran"])
    }
    func testKnownWordsAreNotTreatedAsTypos() {
        let candidates = service(["form": 100, "from": 100_000, "formal": 1_000])
        XCTAssertEqual(candidates.candidates(for: "form"), ["form", "formal"])
    }
    func testCaseApostropheAndUnicodeNormalization() {
        let candidates = service(["hello": 10_000, "don't": 20_000, "café": 100])
        XCTAssertEqual(candidates.candidates(for: "HEL")[1], "HELLO")
        XCTAssertEqual(candidates.candidates(for: "Hel")[1], "Hello")
        XCTAssertTrue(candidates.candidates(for: "dont").contains("don't"))
        XCTAssertEqual(candidates.candidates(for: "don’")[1], "don't")
        XCTAssertEqual(candidates.candidates(for: "cafe\u{301}"), ["cafe\u{301}"])
    }
    func testSavedWordsOutrankGeneralVocabularyAndDeduplicate() {
        let suite = "JBoardDictionaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let personal = PersonalDictionary(defaults: defaults)
        personal.add("Newbigin"); personal.add("NEWBIGIN")
        let candidates = CandidateService(lexicons: [FrequencyLexicon(entries: ["new": 50_000, "news": 500_000, "newbigin": 5]), personal])
        XCTAssertEqual(candidates.candidates(for: "new")[1], "Newbigin")
        XCTAssertEqual(personal.words.count, 1)
    }
    func testEmptyLongAndUnmatchedInputRemainsSafe() {
        let candidates = service(["hello": 100])
        XCTAssertEqual(candidates.candidates(for: ""), [])
        XCTAssertEqual(candidates.candidates(for: "xqz"), ["xqz"])
        let long = String(repeating: "z", count: 100)
        XCTAssertEqual(candidates.candidates(for: long), [long])
    }
    func testParserBOMMalformedRecordsAndDuplicateCounts() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "\u{feff}the 100\nhelp 300\nhelp 1\nhello 200\nbad garbage\nzero 0\nnegative -1\n".write(to: url, atomically: true, encoding: .utf8)
        let lexicon = try FrequencyLexicon(contentsOf: url)
        XCTAssertEqual(lexicon.count, 3)
        XCTAssertEqual(lexicon.completions(for: "hel"), ["help", "hello"])
    }
    func testBundledDictionaryIsPresentAndProducesRealSuggestions() {
        let lexicon = BundledLexicon()
        XCTAssertFalse(lexicon.isFallback)
        XCTAssertEqual(lexicon.count, 82_834)
        let candidates = CandidateService(lexicons: [lexicon])
        for (input, expected) in [("teh", "the"), ("recieve", "receive"), ("wster", "water"), ("nitrific", "nitrification")] {
            let result = candidates.candidates(for: input)
            print("Dictionary example: \(input) → \(result)")
            XCTAssertEqual(result.first, input)
            XCTAssertTrue(result.contains(expected), "\(input): \(result)")
        }
    }
    func testDictionaryLookupTiming() {
        let candidates = CandidateService(lexicons: [BundledLexicon()])
        let inputs = ["a", "th", "hel", "recieve", "wster", "nitrific", "denitrific", "supercalifragilistic"]
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<10 { for input in inputs { _ = candidates.candidates(for: input) } }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 80
        print(String(format: "Average dictionary lookup, Mac debug build: %.2f ms", milliseconds))
        XCTAssertLessThan(milliseconds, 100, "Catch accidental unbounded scans; actual phone latency needs measurement.")
    }
}
