import Foundation

/// Future UI sampling can supply normalized key-plane coordinates and elapsed seconds.
public struct SwipeSample {
    public let x: Double
    public let y: Double
    public let time: TimeInterval
    public init(x: Double, y: Double, time: TimeInterval) { self.x = x; self.y = y; self.time = time }
}
public protocol SwipeDecoding {
    func decode(samples: [SwipeSample], precedingText: String) -> [String]
}
/// No-op decoder retained for integrations that disable swipe input.
public struct DisabledSwipeDecoder: SwipeDecoding {
    public init() {}
    public func decode(samples: [SwipeSample], precedingText: String) -> [String] { [] }
}


public struct SwipeKey {
    public let letter: String
    public let x: Double
    public let y: Double
    public init(letter: String, x: Double, y: Double) { self.letter = letter; self.x = x; self.y = y }
}
public struct SwipeWord {
    public let word: String
    public let frequency: Int64
    public init(word: String, frequency: Int64) { self.word = word; self.frequency = frequency }
}

/// Shape matching on a serial background queue. Uses actual visible key centers,
/// endpoint pruning, spatial resampling and banded dynamic time warping.
public final class LocalSwipeDecoder {
    private let buckets: [String: [SwipeWord]]
    public init(words: [SwipeWord]) {
        let eligible = words.filter { (2...20).contains($0.word.count) && $0.word.utf8.allSatisfy { (97...122).contains($0) } }
        buckets = Dictionary(grouping: eligible) { String($0.word.first!) + String($0.word.last!) }
    }
    private struct Point { let x: Double; let y: Double }
    private func distance(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }
    private func length(_ points: [Point]) -> Double { zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) } }
    private func resample(_ points: [Point], count: Int = 24) -> [Point] {
        guard let first = points.first, let last = points.last else { return [] }
        let total = length(points)
        guard total > 0.001 else { return Array(repeating: first, count: count) }
        var output = [first], segment = 1, traversed = 0.0
        for index in 1..<(count - 1) {
            let target = total * Double(index) / Double(count - 1)
            while segment < points.count - 1 && traversed + distance(points[segment - 1], points[segment]) < target {
                traversed += distance(points[segment - 1], points[segment]); segment += 1
            }
            let a = points[segment - 1], b = points[segment]
            let fraction = min(1, max(0, (target - traversed) / max(0.001, distance(a, b))))
            output.append(Point(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction))
        }
        output.append(last); return output
    }
    private func warpedDistance(_ a: [Point], _ b: [Point]) -> Double {
        var previous = Array(repeating: Double.infinity, count: b.count + 1); previous[0] = 0
        for i in 1...a.count {
            var current = Array(repeating: Double.infinity, count: b.count + 1)
            for j in max(1, i - 5)...min(b.count, i + 5) {
                current[j] = distance(a[i - 1], b[j - 1]) + min(previous[j - 1], previous[j] + 0.04, current[j - 1] + 0.04)
            }
            previous = current
        }
        return previous[b.count] / Double(a.count)
    }
    public func decode(samples: [SwipeSample], keys: [SwipeKey], preferred: [String] = [], personal: [String] = []) -> [String] {
        guard (2...256).contains(samples.count), keys.count == 26,
              samples.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.time.isFinite }),
              keys.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              Set(keys.map(\.letter)).count == 26 else { return [] }
        let observed = samples.map { Point(x: $0.x, y: $0.y) }
        guard length(observed) >= 0.7, samples.last!.time - samples.first!.time <= 8,
              zip(samples, samples.dropFirst()).allSatisfy({ $0.time <= $1.time }) else { return [] }
        let centers = Dictionary(uniqueKeysWithValues: keys.map { ($0.letter, Point(x: $0.x, y: $0.y)) })
        func endpoints(_ point: Point) -> Set<String> {
            Set(keys.sorted { distance(point, centers[$0.letter]!) < distance(point, centers[$1.letter]!) }
                .prefix(3).filter { distance(point, centers[$0.letter]!) <= 1.25 }.map(\.letter))
        }
        let starts = endpoints(observed.first!), ends = endpoints(observed.last!)
        let path = resample(observed), pathLength = length(observed)
        var scored: [(word: String, rough: Double, shape: [Point], bonus: Double)] = []
        var seen = Set<String>()
        let personalEntries = personal.map { SwipeWord(word: normalizedWord($0), frequency: 1_000_000) }
        let nearbyWords = starts.sorted().flatMap { first in ends.sorted().flatMap { last in buckets[first + last] ?? [] } }
        for entry in personalEntries + nearbyWords {
            guard let first = entry.word.first, let last = entry.word.last,
                  starts.contains(String(first)), ends.contains(String(last)), seen.insert(entry.word).inserted else { continue }
            var template: [Point] = []
            for letter in entry.word {
                guard let point = centers[String(letter)] else { template = []; break }
                if template.last.map({ distance($0, point) > 0.001 }) ?? true { template.append(point) }
            }
            guard template.count >= 2 else { continue }
            let shape = resample(template)
            let spatial = zip(path, shape).reduce(0) { $0 + distance($1.0, $1.1) } / Double(path.count)
            let endpoint = (distance(observed.first!, template.first!) + distance(observed.last!, template.last!)) * 0.35
            let lengthPenalty = abs(log((pathLength + 0.5) / (length(template) + 0.5))) * 0.18
            let bonus = log10(Double(max(1, entry.frequency))) * 0.035 + (preferred.contains(entry.word) ? 0.12 : 0)
            scored.append((entry.word, spatial + endpoint + lengthPenalty, shape, bonus))
        }
        let finalists = scored.sorted { $0.rough - $0.bonus < $1.rough - $1.bonus }.prefix(60).map { item in
            (word: item.word, geometry: 0.4 * item.rough + 0.6 * warpedDistance(path, item.shape), bonus: item.bonus)
        }.filter { $0.geometry < 1.0 }.sorted {
            let a = $0.geometry - $0.bonus, b = $1.geometry - $1.bonus
            return a == b ? $0.word < $1.word : a < b
        }
        return Array(finalists.prefix(3).map(\.word))
    }
}
