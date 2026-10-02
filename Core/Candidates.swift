import Foundation

public protocol CandidateScoring {
    func ranked(prefix: String, matches: [LexiconMatch], limit: Int) -> [String]
}

/// Word frequency and edit cost rank suggestions. A matching saved word has
/// priority, and one completion slot is reserved while a word is being typed.
public struct FrequencyCandidateScorer: CandidateScoring {
    public init() {}
    public func ranked(prefix: String, matches: [LexiconMatch], limit: Int) -> [String] {
        guard !prefix.isEmpty, limit > 0 else { return [] }
        let query = normalizedWord(prefix)
        func score(_ match: LexiconMatch) -> Double {
            if match.personal { return 100 - Double(match.word.count) * 0.01 }
            return log10(Double(max(1, match.frequency))) - 1.4 * match.editCost
                - 0.08 * Double(max(0, match.word.count - prefix.count))
        }
        let ranked = matches.sorted {
            let left = score($0), right = score($1)
            return left == right ? normalizedWord($0.word) < normalizedWord($1.word) : left > right
        }
        var seen = Set([query])
        let unique = ranked.filter { seen.insert(normalizedWord($0.word)).inserted }
        var ordered: [LexiconMatch] = []
        // Genuine completions should not disappear behind common short corrections.
        // If no completion exists (e.g. "teh"), use the best typo candidates.
        if let completion = unique.first(where: { normalizedWord($0.word).hasPrefix(query) && $0.editCost == 0 }) {
            let bestScore = unique.first.map(score) ?? 0
            if score(completion) >= bestScore - 1 { ordered.append(completion) }
        }
        ordered += unique.filter { match in !ordered.contains(where: { normalizedWord($0.word) == normalizedWord(match.word) }) }
        func caseMatched(_ word: String) -> String {
            if prefix == prefix.uppercased(), prefix.count > 1 { return word.uppercased() }
            if prefix.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
            return word == "i" ? "I" : word
        }
        return Array(([prefix] + ordered.map { caseMatched($0.word) }).prefix(limit))
    }
}

public struct CandidateService {
    private let lexicons: [any LexiconService]
    private let scorer: any CandidateScoring
    private let nextWords: WordPairPredictor?
    private let learnedPairs: LearnedWordPairs?
    private let exclusions: SuggestionExclusions?
    public init(lexicons: [any LexiconService], scorer: any CandidateScoring = FrequencyCandidateScorer(), nextWords: WordPairPredictor? = nil, learnedPairs: LearnedWordPairs? = nil, exclusions: SuggestionExclusions? = nil) {
        self.lexicons = lexicons
        self.scorer = scorer
        self.nextWords = nextWords
        self.learnedPairs = learnedPairs
        self.exclusions = exclusions
    }
    public func allowsSuggestion(_ word: String) -> Bool { exclusions?.contains(word) != true }
    public func nextWordCandidates(after context: String) -> [String] {
        var seen = Set<String>()
        return Array(((learnedPairs?.suggestions(after: context) ?? []) +
            (nextWords?.suggestions(after: context) ?? [])).filter {
                exclusions?.contains($0) != true && seen.insert(normalizedWord($0)).inserted
            }.prefix(3))
    }
    /// Only real prefix completions influence touches; typo corrections never do.
    /// No touch coordinates or typing offsets are recorded.
    public func nextLetterWeights(for prefix: String) -> [String: Double] {
        let query = normalizedWord(prefix)
        guard !query.isEmpty, query.count <= 24,
              query.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [:] }
        var words: [String: Double] = [:]
        for match in lexicons.flatMap({ $0.matches(for: query) }) {
            let word = normalizedWord(match.word)
            guard match.editCost == 0, word.hasPrefix(query), word.count > query.count,
                  exclusions?.contains(word) != true else { continue }
            let weight = sqrt(Double(max(1, match.frequency))) * (match.personal ? 4 : 1)
            words[word] = max(words[word] ?? 0, weight)
        }
        var weights: [String: Double] = [:]
        for (word, weight) in words {
            let letter = word.dropFirst(query.count).prefix(1)
            guard let character = letter.first, character.isASCII, character.isLetter else { continue }
            weights[String(letter), default: 0] += weight
        }
        guard let maximum = weights.values.max(), maximum > 0 else { return [:] }
        return weights.mapValues { $0 / maximum }
    }
    public func candidates(for prefix: String) -> [String] {
        // Filter before ranking so suppressed words cannot consume candidate slots.
        let matches = lexicons.flatMap { $0.matches(for: prefix) }.filter { exclusions?.contains($0.word) != true }
        return Array(scorer.ranked(prefix: prefix, matches: matches, limit: 4)
            .filter { exclusions?.contains($0) != true }.prefix(3))
    }
}

/// Small on-device bigram model. Stores only the top three continuations for
/// each known preceding word, rather than loading the full upstream corpus.
public final class WordPairPredictor {
    private let pairs: [String: [String]]
    public var contextCount: Int { pairs.count }
    public init(pairs: [String: [String]]) {
        self.pairs = pairs
    }
    public convenience init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var pairs: [String: [String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count >= 2 else { continue }
            pairs[fields[0]] = Array(fields.dropFirst().prefix(3))
        }
        self.init(pairs: pairs)
    }
    public static let bundled: WordPairPredictor = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        if let url = bundle.url(forResource: "english-next-words", withExtension: "txt"),
           let model = try? WordPairPredictor(contentsOf: url) { return model }
        return WordPairPredictor(pairs: [:])
    }()
    public func suggestions(after context: String) -> [String] {
        guard let word = Self.precedingWord(in: context) else { return [] }
        return (pairs[word] ?? []).map { $0 == "i" ? "I" : $0 }
    }
    static func precedingWord(in context: String) -> String? {
        // Only predict once a separator completes the word. Stop at sentence or
        // line boundaries; unigram starters would imply context we do not have.
        guard context.last?.isWhitespace == true else { return nil }
        var preceding = context.trimmingCharacters(in: .whitespaces)
        guard let last = preceding.last, !".!?\n\r".contains(last) else { return nil }
        while let last = preceding.last, ",;:)]}\"”".contains(last) { preceding.removeLast() }
        guard preceding.last?.isLetter == true else { return nil }
        let word = String(preceding.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }.reversed())
        return normalizedWord(word)
    }
}


/// Bounded personal bigrams, stored only in the keyboard extension's defaults.
public final class LearnedWordPairs {
    private struct Entry: Codable {
        var previous: String
        var word: String
        var count: Int
        var sequence: Int
    }
    private let defaults: UserDefaults
    private let capacity: Int
    private let exclusions: SuggestionExclusions?
    private let key = "learnedWordPairs.v1"
    private var entries: [Entry]
    private var sequence: Int
    public var count: Int { entries.count }
    public init(defaults: UserDefaults = .standard, capacity: Int = 5000, exclusions: SuggestionExclusions? = nil) {
        self.defaults = defaults
        self.capacity = max(1, capacity)
        self.exclusions = exclusions
        let loaded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        entries = Array(loaded.sorted { $0.sequence > $1.sequence }.prefix(max(1, capacity)))
        sequence = entries.map(\.sequence).max() ?? 0
    }
    public func record(previous: String, word: String) {
        func valid(_ text: String) -> Bool {
            !text.isEmpty && text.count <= 48 && text.first?.isLetter == true && text.last?.isLetter == true &&
                text.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" }
        }
        guard valid(previous), valid(word), exclusions?.contains(previous) != true, exclusions?.contains(word) != true else { return }
        let previous = normalizedWord(previous), word = normalizedWord(word)
        sequence += 1
        if let index = entries.firstIndex(where: { $0.previous == previous && $0.word == word }) {
            entries[index].count = min(10000, entries[index].count + 1)
            entries[index].sequence = sequence
        } else {
            entries.append(Entry(previous: previous, word: word, count: 1, sequence: sequence))
        }
        if entries.count > capacity {
            entries.sort { $0.sequence > $1.sequence }
            entries.removeLast(entries.count - capacity)
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
    public func suggestions(after context: String) -> [String] {
        guard let previous = WordPairPredictor.precedingWord(in: context) else { return [] }
        return entries.filter { $0.previous == previous }.sorted {
            $0.count == $1.count ? $0.sequence > $1.sequence : $0.count > $1.count
        }.prefix(3).map { $0.word == "i" ? "I" : $0.word }
    }
    public func remove(_ word: String) {
        let normalized = normalizedWord(word)
        entries.removeAll { $0.word == normalized || $0.previous == normalized }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
    public func removeAll() { entries.removeAll(); sequence = 0; defaults.removeObject(forKey: key) }
}

public enum KeyboardLayoutPolicy {
    public static func returnsToLetters(after text: String) -> Bool {
        [".", ",", "?", "!", ";", ":", "\n"].contains(text)
    }
}


/// Explicitly dismissed words stay hidden across launches and future typing.
public final class SuggestionExclusions {
    private let defaults: UserDefaults
    private let key = "hiddenSuggestions.v1"
    private var words: Set<String>
    public var count: Int { words.count }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        words = Set((defaults.stringArray(forKey: key) ?? []).map(normalizedWord))
    }
    public func contains(_ word: String) -> Bool { words.contains(normalizedWord(word)) }
    public func hide(_ word: String) {
        guard !word.isEmpty, word.count <= 48 else { return }
        words.insert(normalizedWord(word))
        defaults.set(words.sorted(), forKey: key)
    }
    public func removeAll() { words.removeAll(); defaults.removeObject(forKey: key) }
}
