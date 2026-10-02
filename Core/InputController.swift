import Foundation

/// UIKit adapter supplies the current UITextDocumentProxy on every access.
public protocol TextDocument: AnyObject {
    var beforeInput: String? { get }
    var afterInput: String? { get }
    var selection: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
}

public enum ShiftState { case off, once, locked }

public final class InputController {
    public private(set) var shift: ShiftState = .off
    public private(set) var nextLetterWeights: [String: Double] = [:]
    public private(set) var candidates: [String] = []
    private let touchCalibration: TouchCalibration?
    private var touchWord = ""
    private var wordTouches: [LetterTouch] = []
    private var touchBefore: String?
    private var touchAfter: String?
    private struct SwipeReplacement {
        var inserted: String
        var before: String?
        var after: String?
        var choices: [String]
    }
    private var swipeReplacement: SwipeReplacement?
    public func clearSwipeReplacement() { swipeReplacement = nil }
    public var canInsertSwipe: Bool {
        document.beforeInput != nil && document.selection?.isEmpty != false && currentWord.isEmpty &&
            document.beforeInput?.last?.isNumber != true &&
            document.afterInput?.first.map(Self.isWordCharacter) != true
    }
    @discardableResult public func insertSwipe(_ words: [String]) -> Bool {
        guard settings.swipeEnabled, canInsertSwipe else { return false }
        var seen = Set<String>()
        let choices = words.filter { candidateService.allowsSuggestion($0) && seen.insert(normalizedWord($0)).inserted }
            .filter { !$0.isEmpty && $0.count <= 48 && $0.allSatisfy({ $0.isLetter }) }.prefix(3).map { word in
                shift == .locked ? word.uppercased() : shift == .once ? word.prefix(1).uppercased() + word.dropFirst() : word == "i" ? "I" : word
            }
        guard let best = choices.first else { return false }
        resetLearningSession(); resetTouchCalibrationSession()
        let inserted = best + ((document.afterInput ?? "").isEmpty ? " " : "")
        document.insertText(inserted)
        if shift == .once { shift = .off }
        swipeReplacement = SwipeReplacement(inserted: inserted, before: document.beforeInput,
            after: document.afterInput, choices: choices)
        refresh(); return true
    }
    private func validSwipeReplacement() -> SwipeReplacement? {
        guard let state = swipeReplacement, document.beforeInput == state.before,
              document.afterInput == state.after, document.selection?.isEmpty != false else { return nil }
        return state
    }
    private let document: any TextDocument
    private let candidateService: CandidateService
    private let settings: KeyboardSettings
    private let learnedPairs: LearnedWordPairs?
    private var learnedPrevious: String?
    private var ownedWord = ""
    private var blockedToken = false
    private var expectedBefore: String?
    private var expectedAfter: String?
    private var hasExpectedContext = false
    private var snapshotBefore: String?
    private var snapshotAfter: String?
    private var snapshotWord = ""

    public init(document: any TextDocument, candidates: CandidateService, settings: KeyboardSettings, learnedPairs: LearnedWordPairs? = nil, touchCalibration: TouchCalibration? = nil) {
        self.document = document
        self.candidateService = candidates
        self.settings = settings
        self.learnedPairs = learnedPairs
        self.touchCalibration = touchCalibration
    }
    public func toggleShift() { shift = shift == .off ? .once : .off }
    public func lockShift() { shift = shift == .locked ? .off : .locked }
    public func resetTouchCalibrationSession() {
        touchWord = ""; wordTouches = []; touchBefore = nil; touchAfter = nil
    }
    private func validateTouchSession() {
        if !settings.touchCalibrationEnabled || document.selection?.isEmpty == false ||
            document.beforeInput == nil || !(document.afterInput ?? "").isEmpty ||
            (!touchWord.isEmpty && (document.beforeInput != touchBefore || document.afterInput != touchAfter)) {
            resetTouchCalibrationSession()
        }
    }
    public func type(_ text: String, touch: LetterTouch? = nil) {
        if let state = validSwipeReplacement(), state.inserted.hasSuffix(" ") {
            swipeReplacement = nil
            if text == " " { refresh(); return }
            if [".", ",", "?", "!", ";", ":", "\n"].contains(text) { document.deleteBackward() }
        }
        swipeReplacement = nil
        validateTouchSession()
        if settings.touchCalibrationEnabled, document.beforeInput != nil,
           document.selection?.isEmpty != false, (document.afterInput ?? "").isEmpty,
           normalizedWord(currentWord) == touchWord, let touch,
           text.count == 1, text.first?.isASCII == true, text.first?.isLetter == true,
           touch.letter == normalizedWord(text), wordTouches.count < 24 {
            touchWord += normalizedWord(text); wordTouches.append(touch)
        } else { resetTouchCalibrationSession() }
        validateLearningContext()
        let inserted = shift == .off ? text : text.uppercased()
        learn(inserted)
        document.insertText(inserted)
        rememberContext()
        touchBefore = document.beforeInput; touchAfter = document.afterInput
        if shift == .once && text.contains(where: { $0.isLetter }) { shift = .off }
        refresh()
    }
    public func backspace() {
        resetTouchCalibrationSession(); resetLearningSession()
        if let state = validSwipeReplacement() {
            for _ in state.inserted { document.deleteBackward() }
        } else { document.deleteBackward() }
        swipeReplacement = nil; refresh()
    }
    public func resetLearningSession() {
        learnedPrevious = nil; ownedWord = ""; blockedToken = false; hasExpectedContext = false
    }
    private func validateLearningContext() {
        if !settings.wordLearningEnabled || document.beforeInput == nil || document.selection?.isEmpty == false ||
            !(document.afterInput ?? "").isEmpty ||
            (hasExpectedContext && (document.beforeInput != expectedBefore || document.afterInput != expectedAfter)) {
            resetLearningSession()
        }
        if !hasExpectedContext {
            // A partially existing token must never become a learned word.
            blockedToken = document.beforeInput?.last.map { !$0.isWhitespace } ?? false
        }
    }
    private func rememberContext() {
        expectedBefore = document.beforeInput; expectedAfter = document.afterInput; hasExpectedContext = true
    }
    private func learn(_ text: String) {
        guard settings.wordLearningEnabled, document.beforeInput != nil,
              document.selection?.isEmpty != false, (document.afterInput ?? "").isEmpty else { return }
        for character in text {
            if Self.isWordCharacter(character) {
                if !blockedToken { ownedWord.append(character) }
                if ownedWord.count > 48 { ownedWord = ""; blockedToken = true; learnedPrevious = nil }
            } else if character.isWhitespace || ".,!?;:".contains(character) {
                if blockedToken && !character.isWhitespace { continue }
                if !blockedToken && !ownedWord.isEmpty {
                    if let previous = learnedPrevious { learnedPairs?.record(previous: previous, word: ownedWord) }
                    learnedPrevious = ownedWord
                } else if blockedToken { learnedPrevious = nil }
                ownedWord = ""; blockedToken = false
                if !character.isWhitespace || character.isNewline { learnedPrevious = nil }
            } else {
                // Do not learn numeric, email, URL, or other mixed tokens.
                ownedWord = ""; blockedToken = true; learnedPrevious = nil
            }
        }
    }
    public func refresh() {
        validateTouchSession()
        validateLearningContext()
        if let state = validSwipeReplacement() {
            candidates = settings.candidatesEnabled ? state.choices.filter(candidateService.allowsSuggestion) : []
            nextLetterWeights = [:]
            return
        }
        swipeReplacement = nil
        snapshotBefore = document.beforeInput
        snapshotAfter = document.afterInput
        snapshotWord = Self.wordSuffix(snapshotBefore ?? "")
        // Do not offer replacements on selections, unavailable context, or inside words.
        // A nil trailing context can simply mean the cursor is at the end.
        let insideWord = snapshotAfter?.first.map(Self.isWordCharacter) ?? false
        nextLetterWeights = [:]
        guard snapshotBefore != nil,
              document.selection?.isEmpty != false, !insideWord else {
            candidates = []; return
        }
        if settings.dynamicKeyTargetsEnabled {
            nextLetterWeights = candidateService.nextLetterWeights(for: snapshotWord)
        }
        guard settings.candidatesEnabled else { candidates = []; return }
        candidates = snapshotWord.isEmpty
            ? candidateService.nextWordCandidates(after: snapshotBefore ?? "")
            : candidateService.candidates(for: snapshotWord)
    }
    @discardableResult public func accept(_ candidate: String) -> Bool {
        if var state = validSwipeReplacement(), candidates.contains(candidate), candidateService.allowsSuggestion(candidate) {
            for _ in state.inserted { document.deleteBackward() }
            state.inserted = candidate + (state.inserted.hasSuffix(" ") ? " " : "")
            document.insertText(state.inserted)
            state.before = document.beforeInput; state.after = document.afterInput
            swipeReplacement = state; refresh(); return true
        }
        if swipeReplacement != nil { swipeReplacement = nil; refresh(); return false }
        guard candidates.contains(candidate),
              document.beforeInput == snapshotBefore, document.afterInput == snapshotAfter,
              document.selection?.isEmpty != false else {
            refresh(); return false
        }
        validateTouchSession()
        if settings.touchCalibrationEnabled, touchWord == normalizedWord(snapshotWord) {
            touchCalibration?.learn(typed: snapshotWord, corrected: candidate, touches: wordTouches)
        }
        resetTouchCalibrationSession()
        validateLearningContext()
        // Only retain the previous word when replacing our own partial token.
        if ownedWord != snapshotWord { resetLearningSession() }
        ownedWord = ""; blockedToken = false
        // Next-word predictions have an empty snapshotWord: insert without deleting.
        // Completions delete Characters, not UTF-16 code units (composed accents).
        for _ in snapshotWord { document.deleteBackward() }
        // Completing at the end starts the next word. In existing text, leave
        // its whitespace/punctuation in place instead of introducing a gap.
        let suffix = (snapshotAfter ?? "").isEmpty ? " " : ""
        learn(candidate + suffix)
        document.insertText(candidate + suffix)
        rememberContext()
        if shift == .once { shift = .off }
        refresh()
        return true
    }
    public var currentWord: String {
        guard document.selection?.isEmpty != false,
              document.afterInput?.first.map(Self.isWordCharacter) != true else { return "" }
        return Self.wordSuffix(document.beforeInput ?? "")
    }
    private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c == "'" || c == "’" }
    private static func wordSuffix(_ text: String) -> String {
        String(text.reversed().prefix(while: isWordCharacter).reversed())
    }
}

/// Monotonic-time gate shared by the UIKit backspace button and deterministic tests.
/// Each press can fire once; cancellation permanently disarms that press.
public struct BackspacePress {
    private var deadline: TimeInterval?
    public init() {}
    public mutating func begin(at time: TimeInterval, delay: TimeInterval) {
        deadline = time + max(0, delay)
    }
    public mutating func cancel() { deadline = nil }
    public func remainingDelay(at time: TimeInterval) -> TimeInterval? {
        deadline.map { max(0, $0 - time) }
    }
    public static func allowsDrift(horizontalOverflow: Double, verticalOverflow: Double) -> Bool {
        horizontalOverflow.isFinite && verticalOverflow.isFinite &&
            max(horizontalOverflow, verticalOverflow) <= 8
    }
    public mutating func consume(at time: TimeInterval) -> Bool {
        guard let deadline, time >= deadline else { return false }
        self.deadline = nil
        return true
    }
}


/// A pending delete belongs to one field and cursor context. Host notifications
/// alone do not invalidate it; actual context changes do.
public struct DeletionContext: Equatable {
    public let documentID: UUID
    public let before: String?
    public let after: String?
    public let selection: String?
    public init(documentID: UUID, before: String?, after: String?, selection: String?) {
        self.documentID = documentID; self.before = before; self.after = after; self.selection = selection
    }
}


/// UIKit can return nil for documentIdentifier before a host field connects,
/// despite its nonoptional Swift declaration. Read the public Objective-C
/// property as a nullable object to avoid UUID's unconditional bridge trap.
public enum DocumentIdentity {
    public static func read(from object: NSObject) -> UUID? {
        guard object.responds(to: NSSelectorFromString("documentIdentifier")) else { return nil }
        guard let identifier = object.value(forKey: "documentIdentifier") as? NSUUID else { return nil }
        return identifier as UUID
    }
}
