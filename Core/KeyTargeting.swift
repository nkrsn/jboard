import Foundation

/// Shared boundary adjustment, in key-plane units. Both neighbors use the same
/// result, so the cells remain gap-free and do not overlap. Centers stay fixed.
public enum KeyTargeting {
    public static func boundary(leftEdge: Double, rightEdge: Double,
                                leftWidth: Double, rightWidth: Double,
                                leftWeight: Double, rightWeight: Double, calibration: Double = 0) -> Double {
        let midpoint = (leftEdge + rightEdge) / 2
        guard leftWidth > 0, rightWidth > 0 else { return midpoint }
        func bounded(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        let maximumShift = min(leftWidth, rightWidth) * 0.12
        let learned = calibration.isFinite ? min(0.12, max(-0.12, calibration)) : 0
        let width = min(leftWidth, rightWidth)
        let shift = maximumShift * (bounded(leftWeight) - bounded(rightWeight)) + width * learned
        return midpoint + min(width * 0.18, max(-width * 0.18, shift))
    }
}


/// Short-lived evidence for a tap near a horizontal letter boundary.
public struct BoundaryTouch {
    public let left: String
    public let right: String
    public let offset: Double
    public init(left: String, right: String, offset: Double) {
        self.left = left; self.right = right; self.offset = offset
    }
}
public struct LetterTouch {
    public let letter: String
    public let boundaries: [BoundaryTouch]
    public init(letter: String, boundaries: [BoundaryTouch]) {
        self.letter = letter; self.boundaries = boundaries
    }
}

/// Saves only aggregate boundary estimates, never words or raw touch trails.
public final class TouchCalibration {
    private struct Estimate: Codable { var count: Int; var mean: Double }
    private let defaults: UserDefaults
    private let key = "portraitTouchCalibration.v1"
    private var estimates: [String: Estimate]
    private static let allowed: Set<String> = Set(["qwertyuiop", "asdfghjkl", "zxcvbnm"].flatMap { row in
        zip(row, row.dropFirst()).map { "\($0)\($1)" }
    })
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Estimate].self, from: $0) } ?? [:]
        estimates = decoded.filter { Self.allowed.contains($0.key) && $0.value.count > 0 &&
            $0.value.count <= 50 && $0.value.mean.isFinite && abs($0.value.mean) <= 0.12 }
    }
    public var correctionCount: Int { estimates.values.reduce(0) { $0 + $1.count } }
    public func adjustment(left: String, right: String) -> Double {
        guard let estimate = estimates[left + right], estimate.count >= 5 else { return 0 }
        // Five confirmations before any movement; full effect only after twenty.
        return estimate.mean * min(1, Double(estimate.count - 4) / 16)
    }
    @discardableResult public func learn(typed: String, corrected: String, touches: [LetterTouch]) -> Bool {
        let typed = Array(normalizedWord(typed)), corrected = Array(normalizedWord(corrected))
        guard typed.count >= 2, typed.count <= 24, typed.count == corrected.count,
              touches.count == typed.count,
              typed.allSatisfy({ $0.isASCII && $0.isLetter }),
              corrected.allSatisfy({ $0.isASCII && $0.isLetter }),
              zip(typed, touches).allSatisfy({ String($0) == $1.letter }) else { return false }
        let changes = typed.indices.filter { typed[$0] != corrected[$0] }
        guard changes.count == 1, let index = changes.first else { return false }
        let original = String(typed[index]), intended = String(corrected[index])
        guard let edge = touches[index].boundaries.first(where: {
            ($0.left == original && $0.right == intended) || ($0.right == original && $0.left == intended)
        }), Self.allowed.contains(edge.left + edge.right), edge.offset.isFinite, abs(edge.offset) <= 0.18 else { return false }
        let desired = intended == edge.left ? max(0.02, edge.offset + 0.03) : min(-0.02, edge.offset - 0.03)
        let bounded = min(0.12, max(-0.12, desired))
        let name = edge.left + edge.right
        var estimate = estimates[name] ?? Estimate(count: 0, mean: 0)
        estimate.count = min(50, estimate.count + 1)
        estimate.mean += (bounded - estimate.mean) / Double(estimate.count)
        estimates[name] = estimate
        if let data = try? JSONEncoder().encode(estimates) { defaults.set(data, forKey: key) }
        return true
    }
    public func reset() { estimates.removeAll(); defaults.removeObject(forKey: key) }
}
