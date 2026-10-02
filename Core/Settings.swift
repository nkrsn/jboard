import Foundation

/// The extension uses its own defaults. No App Group or Full Access is needed.
public final class KeyboardSettings {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var cursorPadEnabled: Bool {
        get { defaults.object(forKey: "cursorPadEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cursorPadEnabled") }
    }
    public var swipeEnabled: Bool {
        get { defaults.object(forKey: "swipeEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "swipeEnabled") }
    }
    public var touchCalibrationEnabled: Bool {
        get { defaults.object(forKey: "touchCalibrationEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "touchCalibrationEnabled") }
    }
    public var dynamicKeyTargetsEnabled: Bool {
        get { defaults.object(forKey: "dynamicKeyTargetsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dynamicKeyTargetsEnabled") }
    }
    public var wordLearningEnabled: Bool {
        get { defaults.object(forKey: "wordLearningEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "wordLearningEnabled") }
    }
    public var candidatesEnabled: Bool {
        get { defaults.object(forKey: "candidatesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "candidatesEnabled") }
    }
    public var backspaceGuardEnabled: Bool {
        get { defaults.object(forKey: "backspaceGuardEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "backspaceGuardEnabled") }
    }
    public var backspaceDelayMilliseconds: Int {
        get {
            let stored = defaults.object(forKey: "backspaceDelayMilliseconds") as? Int ?? 120
            return min(180, max(80, stored))
        }
        set { defaults.set(min(180, max(80, newValue)), forKey: "backspaceDelayMilliseconds") }
    }
    public var keyPreviewsEnabled: Bool {
        get { defaults.object(forKey: "keyPreviewsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "keyPreviewsEnabled") }
    }
}
