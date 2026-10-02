import Foundation

public struct LexiconMatch {
    public let word: String
    public let frequency: Int64
    public let editCost: Double
    public let personal: Bool
    public init(word: String, frequency: Int64 = 1_000, editCost: Double = 0, personal: Bool = false) {
        self.word = word; self.frequency = frequency; self.editCost = editCost; self.personal = personal
    }
}

public protocol LexiconService {
    func completions(for prefix: String) -> [String]
    func matches(for prefix: String) -> [LexiconMatch]
}
public extension LexiconService {
    func matches(for prefix: String) -> [LexiconMatch] {
        completions(for: prefix).map { LexiconMatch(word: $0) }
    }
}

func normalizedWord(_ word: String) -> String {
    word.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "’", with: "'")
}

/// Sorted prefix lookup plus hash lookups for one-edit errors: no full dictionary
/// edit-distance scan and no large precomputed deletion index in the extension.
public final class FrequencyLexicon: LexiconService {
    private let frequencies: [String: Int64]
    private let sortedWords: [String]
    // Immutable dictionary results are reused while typing/backspacing. Bounded
    // to avoid retaining an unbounded history of queried prefixes.
    private var matchCache: [String: [LexiconMatch]] = [:]
    private var cacheOrder: [String] = []
    public var count: Int { sortedWords.count }
    public var swipeWords: [SwipeWord] { frequencies.map { SwipeWord(word: $0.key, frequency: $0.value) } }

    public init(entries: [String: Int64]) {
        var normalized: [String: Int64] = [:]
        for (word, frequency) in entries where frequency > 0 {
            let key = normalizedWord(word)
            guard !key.isEmpty, key.count <= 48,
                  key.allSatisfy({ $0.isLetter || $0 == "'" }) else { continue }
            normalized[key] = max(normalized[key] ?? 0, frequency)
        }
        frequencies = normalized
        sortedWords = normalized.keys.sorted()
    }
    public convenience init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var entries: [String: Int64] = [:]
        entries.reserveCapacity(85_000)
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, let count = Int64(fields[1]), count > 0 else { continue }
            let word = String(fields[0]).replacingOccurrences(of: "\u{feff}", with: "")
            entries[word] = max(entries[word] ?? 0, count)
        }
        self.init(entries: entries)
    }
    public func completions(for prefix: String) -> [String] {
        let query = normalizedWord(prefix)
        guard !query.isEmpty, query.count <= 48 else { return [] }
        var low = 0, high = sortedWords.count
        while low < high {
            let middle = (low + high) / 2
            if sortedWords[middle] < query { low = middle + 1 } else { high = middle }
        }
        var matches: [String] = []
        var index = low
        while index < sortedWords.count && sortedWords[index].hasPrefix(query) {
            matches.append(sortedWords[index]); index += 1
        }
        return Array(matches.sorted {
            let left = frequencies[$0] ?? 0, right = frequencies[$1] ?? 0
            return left == right ? $0 < $1 : left > right
        }.prefix(24))
    }
    public func matches(for prefix: String) -> [LexiconMatch] {
        let query = normalizedWord(prefix)
        guard !query.isEmpty, query.count <= 48 else { return [] }
        if let cached = matchCache[query] { return cached }
        var results = completions(for: query).map { LexiconMatch(word: $0, frequency: frequencies[$0] ?? 1) }
        // Do not propose spelling changes for an already known word. Only generate
        // bounded English variants; personal Unicode words still get completions.
        guard frequencies[query] == nil, (3...24).contains(query.count),
              query.utf8.allSatisfy({ (97...122).contains($0) || $0 == 39 }) else { return cache(results, for: query) }
        let letters = Array(query)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz'")
        var corrections: [String: Double] = [:]
        func consider(_ variant: [Character], cost: Double) {
            let word = String(variant)
            guard word != query, !word.hasPrefix(query) else { return }
            if frequencies[word] != nil {
                corrections[word] = min(corrections[word] ?? .infinity, cost)
            }
            // A one-edit repair may itself be an unfinished prefix: worki → working.
            // Binary prefix lookup avoids scanning the dictionary. Keep short,
            // ambiguous inputs and very long tokens on the existing exact path.
            guard (4...16).contains(query.count), word.count >= 4 else { return }
            for completion in completions(for: word) where completion.count > word.count && !completion.hasPrefix(query) {
                corrections[completion] = min(corrections[completion] ?? .infinity, cost)
            }
        }
        for index in letters.indices {
            var deleted = letters; deleted.remove(at: index); consider(deleted, cost: 1)
            if index + 1 < letters.count {
                var swapped = letters; swapped.swapAt(index, index + 1); consider(swapped, cost: 0.8)
            }
            for letter in alphabet where letter != letters[index] {
                var replaced = letters; replaced[index] = letter; consider(replaced, cost: 1)
            }
        }
        for index in 0...letters.count {
            for letter in alphabet {
                var inserted = letters; inserted.insert(letter, at: index); consider(inserted, cost: 1)
            }
        }
        results += corrections.map { LexiconMatch(word: $0.key, frequency: frequencies[$0.key] ?? 1, editCost: $0.value) }
        return cache(results, for: query)
    }
    private func cache(_ results: [LexiconMatch], for query: String) -> [LexiconMatch] {
        if matchCache.count >= 128, let oldest = cacheOrder.first {
            matchCache.removeValue(forKey: oldest); cacheOrder.removeFirst()
        }
        matchCache[query] = results; cacheOrder.append(query)
        return results
    }
}

/// The same packaged data is used by the extension and Swift package tests.
public final class BundledLexicon: LexiconService {
    private static let loaded: FrequencyLexicon = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        if let url = bundle.url(forResource: "english-frequency", withExtension: "txt"),
           let lexicon = try? FrequencyLexicon(contentsOf: url), lexicon.count > 0 { return lexicon }
        // Keep typing functional if a development build omits the resource.
        return FrequencyLexicon(entries: ["hello": 2_000, "help": 3_000, "the": 10_000])
    }()
    public var count: Int { Self.loaded.count }
    public var swipeWords: [SwipeWord] { Self.loaded.swipeWords }
    public var isFallback: Bool { count < 1_000 }
    public init() {}
    public func completions(for prefix: String) -> [String] { Self.loaded.completions(for: prefix) }
    public func matches(for prefix: String) -> [LexiconMatch] { Self.loaded.matches(for: prefix) }
}

/// Only explicitly saved words persist. Never records typed text automatically.
public final class PersonalDictionary: LexiconService {
    private let defaults: UserDefaults
    private let key = "personalWords"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var words: [String] { defaults.stringArray(forKey: key) ?? [] }
    public func add(_ word: String) {
        guard !word.isEmpty, word.count <= 48, word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return }
        var saved = words
        guard !saved.contains(where: { normalizedWord($0) == normalizedWord(word) }), saved.count < 1000 else { return }
        saved.append(word)
        defaults.set(saved, forKey: key)
    }
    public func remove(_ word: String) {
        defaults.set(words.filter { normalizedWord($0) != normalizedWord(word) }, forKey: key)
    }
    public func removeAll() { defaults.removeObject(forKey: key) }
    public func completions(for prefix: String) -> [String] {
        let query = normalizedWord(prefix)
        guard !query.isEmpty else { return [] }
        return words.filter { normalizedWord($0).hasPrefix(query) }
    }
    public func matches(for prefix: String) -> [LexiconMatch] {
        completions(for: prefix).map { LexiconMatch(word: $0, personal: true) }
    }
}
