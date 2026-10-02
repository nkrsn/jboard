import Foundation

/// Converts trackpad travel to discrete moves, with a dead zone and a dominant
/// axis to prevent a vertical gesture from accumulating unintended side drift.
public struct CursorMotion {
    private var x = 0.0
    private var y = 0.0
    public init() {}
    public mutating func reset() { x = 0; y = 0 }
    public mutating func consume(dx: Double, dy: Double) -> (characters: Int, lines: Int) {
        guard dx.isFinite, dy.isFinite else { reset(); return (0, 0) }
        x = min(108, max(-108, x + dx)); y = min(84, max(-84, y + dy))
        if abs(y) > abs(x) {
            let steps = min(3, max(-3, Int(y / 28)))
            if steps != 0 { y -= Double(steps) * 28; x = 0 }
            return (0, steps)
        }
        let steps = min(12, max(-12, Int(x / 9)))
        if steps != 0 { x -= Double(steps) * 9; y = 0 }
        return (steps, 0)
    }
}

/// UIKit offsets use UTF-16; calculate boundaries with Swift Characters first
/// so composed letters and emoji remain intact. Vertical moves use actual
/// newline characters only: the proxy does not expose visual wrapping.
public struct CursorNavigator {
    private var preferredColumn: Int?
    public init() {}
    public mutating func reset() { preferredColumn = nil }
    public mutating func horizontalOffset(_ steps: Int, before: String, after: String) -> Int {
        preferredColumn = nil
        let bounded = min(12, max(-12, steps))
        return bounded < 0 ? -String(before.suffix(-bounded)).utf16.count : String(after.prefix(bounded)).utf16.count
    }
    public mutating func verticalOffset(_ steps: Int, before: String, after: String) -> Int {
        guard steps != 0 else { return 0 }
        let text = Array(before + after), cursor = before.count
        func start(of position: Int) -> Int {
            guard position > 0 else { return 0 }
            return (text[..<position].lastIndex(where: { $0.isNewline }).map { $0 + 1 }) ?? 0
        }
        func end(of position: Int) -> Int {
            text[position...].firstIndex(where: { $0.isNewline }) ?? text.count
        }
        let column = preferredColumn ?? (cursor - start(of: cursor))
        preferredColumn = column
        var target = cursor
        for _ in 0..<abs(min(3, max(-3, steps))) {
            if steps < 0 {
                let currentStart = start(of: target)
                guard currentStart > 0 else { break }
                let previousEnd = currentStart - 1, previousStart = start(of: previousEnd)
                target = previousStart + min(column, previousEnd - previousStart)
            } else {
                let currentEnd = end(of: target)
                guard currentEnd < text.count else { break }
                let nextStart = currentEnd + 1, nextEnd = end(of: nextStart)
                target = nextStart + min(column, nextEnd - nextStart)
            }
        }
        return target < cursor ? -String(text[target..<cursor]).utf16.count : String(text[cursor..<target]).utf16.count
    }
}
