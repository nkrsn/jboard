import UIKit
import UIKit.UIGestureRecognizerSubclass

enum KeyAction { case text(String), shift, backspace, symbols, settings }

/// Visual key spacing remains, while the assigned touch area includes half of each gap.
private class KeyButton: UIButton {
    var touchBounds: CGRect?
    var expandsTouchArea = true
    var letter: String?
    var captureTouch: ((CGPoint) -> LetterTouch?)?
    var letterTouch: LetterTouch?
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        letterTouch = captureTouch?(touch.location(in: self))
        return super.beginTracking(touch, with: event)
    }
    override func accessibilityActivate() -> Bool {
        letterTouch = nil
        return super.accessibilityActivate()
    }
    override func cancelTracking(with event: UIEvent?) {
        letterTouch = nil; super.cancelTracking(with: event)
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        (touchBounds ?? bounds).contains(point)
    }
}

private final class BackspaceButton: KeyButton {
    var guardEnabled = true
    var holdDelay: TimeInterval = 0.12
    var onDelete: (() -> Void)?
    var prepareDelete: (() -> (() -> Bool))?
    private var deletionAllowed: (() -> Bool)?
    private var press = BackspacePress()
    private var timer: Timer?
    private var contactValid = false

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        cancelPendingPress()
        guard super.beginTracking(touch, with: event) else { return false }
        contactValid = true
        deletionAllowed = prepareDelete?()
        if guardEnabled {
            // Measure the physical press, not when a busy main thread processes it.
            press.begin(at: touch.timestamp, delay: holdDelay)
            scheduleDeadline()
        }
        return true
    }
    private func accepts(_ point: CGPoint) -> Bool {
        BackspacePress.allowsDrift(
            horizontalOverflow: Double(max(bounds.minX - point.x, point.x - bounds.maxX, 0)),
            verticalOverflow: Double(max(bounds.minY - point.y, point.y - bounds.maxY, 0)))
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        // A press must START inside Delete. Small finger drift after that is OK;
        // a deliberate slide away cancels permanently until the next press.
        if !accepts(touch.location(in: self)) { cancelPendingPress() }
        return super.continueTracking(touch, with: event)
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if contactValid, let touch, accepts(touch.location(in: self)) {
            if guardEnabled { fireIfReady(at: touch.timestamp) } else { deleteIfAllowed() }
        }
        cancelPendingPress()
        super.endTracking(touch, with: event)
    }
    private func scheduleDeadline() {
        timer?.invalidate()
        guard contactValid, let remaining = press.remainingDelay(at: ProcessInfo.processInfo.systemUptime) else { return }
        let timer = Timer(timeInterval: max(0.001, remaining), repeats: false) { [weak self] _ in
            guard let self, self.isTracking, self.contactValid, self.window != nil else { return }
            self.fireIfReady(at: ProcessInfo.processInfo.systemUptime)
            // Timers can arrive just before the deadline; do not lose that press.
            self.scheduleDeadline()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func cancelTracking(with event: UIEvent?) {
        cancelPendingPress()
        super.cancelTracking(with: event)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelPendingPress() }
    }
    override func accessibilityActivate() -> Bool {
        // VoiceOver activation is already deliberate and has no sustained touch.
        cancelPendingPress()
        onDelete?()
        return true
    }
    private func deleteIfAllowed() {
        guard deletionAllowed?() != false else { return }
        onDelete?()
    }
    private func fireIfReady(at time: TimeInterval) {
        if press.consume(at: time) {
            timer?.invalidate(); timer = nil
            deleteIfAllowed()
        }
    }
    func cancelPendingPress() {
        contactValid = false
        deletionAllowed = nil
        timer?.invalidate(); timer = nil
        press.cancel()
    }
    deinit { timer?.invalidate() }
}

/// Stays possible during a normal tap; only a deliberate letter-to-letter drag
/// cancels the original button. No delay is introduced into tap delivery.
private final class LetterSwipeGesture: UIGestureRecognizer {
    var threshold: CGFloat = 28
    private(set) var samples: [SwipeSample] = []
    private var origin = CGPoint.zero
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, numberOfTouches <= 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled; return
        }
        origin = touch.location(in: view); append(touch)
    }
    private func append(_ touch: UITouch) {
        let point = touch.location(in: view)
        if let last = samples.last, hypot(point.x - last.x, point.y - last.y) < 2 { return }
        if samples.count >= 255 { samples = samples.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }
        samples.append(SwipeSample(x: point.x, y: point.y, time: touch.timestamp))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        append(touch)
        if let first = samples.first, touch.timestamp - first.time > 8 { state = .cancelled; return }
        let point = touch.location(in: view)
        if state == .possible {
            if hypot(point.x - origin.x, point.y - origin.y) >= threshold { state = .began }
        } else { state = .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { append(touch) }
        state = state == .possible ? .failed : .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() { super.reset(); samples = [] }
}

/// A tap remains a space. A 300ms hold or 12-point drag captures the gesture
/// for cursor movement, even after the finger leaves the spacebar.
private final class CursorPadGesture: UIGestureRecognizer {
    private(set) var origin = CGPoint.zero
    private(set) var location = CGPoint.zero
    private var timer: Timer?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, numberOfTouches <= 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled; return
        }
        origin = touch.location(in: view); location = origin
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self, self.state == .possible else { return }
            self.state = .began
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        location = touch.location(in: view)
        if state == .possible {
            if hypot(location.x - origin.x, location.y - origin.y) >= 12 {
                timer?.invalidate(); state = .began
            }
        } else { state = .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.invalidate()
        if let touch = touches.first { location = touch.location(in: view) }
        state = state == .possible ? .failed : .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.invalidate(); state = .cancelled
    }
    override func reset() { timer?.invalidate(); timer = nil; super.reset() }
    deinit { timer?.invalidate() }
}

final class KeyboardView: UIView, UIGestureRecognizerDelegate {
    var canBeginCursorPad: (() -> Bool)?
    var onCursorPadBegan: (() -> Void)?
    var onCursorMove: ((Int, Int) -> Void)?
    var onCursorPadEnded: (() -> Void)?
    var cursorPadEnabled = true { didSet { cursorGesture.isEnabled = cursorPadEnabled } }
    private var spaceButton: UIButton?
    private var cursorPadActive = false
    private var cursorMotion = CursorMotion()
    private var lastCursorPoint = CGPoint.zero
    private let cursorOverlay = UILabel()
    private lazy var cursorGesture: CursorPadGesture = {
        let gesture = CursorPadGesture(target: self, action: #selector(handleCursorPad(_:)))
        gesture.delegate = self; gesture.cancelsTouchesInView = true
        gesture.delaysTouchesBegan = false; gesture.delaysTouchesEnded = false
        return gesture
    }()
    func cancelCursorPad() {
        cursorGesture.isEnabled = false; cursorGesture.isEnabled = cursorPadEnabled
        finishCursorPad()
    }
    private func finishCursorPad() {
        guard cursorPadActive else { return }
        cursorPadActive = false; cursorOverlay.isHidden = true; rows.alpha = 1
        cursorMotion.reset(); onCursorPadEnded?()
    }
    private func moveCursorPad(to point: CGPoint) {
        let movement = cursorMotion.consume(dx: point.x - lastCursorPoint.x, dy: point.y - lastCursorPoint.y)
        lastCursorPoint = point
        if movement.characters != 0 || movement.lines != 0 { onCursorMove?(movement.characters, movement.lines) }
    }
    @objc private func handleCursorPad(_ gesture: CursorPadGesture) {
        switch gesture.state {
        case .began:
            cursorPadActive = true; cursorMotion.reset(); lastCursorPoint = gesture.origin
            cancelSwipe(); cancelPendingBackspace(); dismissKeyPreview()
            rows.alpha = 0.2
            cursorOverlay.frame = rows.convert(rows.bounds, to: self)
            cursorOverlay.isHidden = false; bringSubviewToFront(cursorOverlay)
            showSwipeStatus("Cursor control · release to type")
            onCursorPadBegan?(); moveCursorPad(to: gesture.location)
        case .changed: moveCursorPad(to: gesture.location)
        case .ended:
            moveCursorPad(to: gesture.location); finishCursorPad()
        case .cancelled, .failed: finishCursorPad()
        default: break
        }
    }
    var canBeginSwipe: (() -> Bool)?
    var onSwipeBegan: (() -> Void)?
    var onSwipe: (([SwipeSample], [SwipeKey]) -> Void)?
    var swipeEnabled = true { didSet { swipeGesture.isEnabled = swipeEnabled } }
    private lazy var swipeGesture: LetterSwipeGesture = {
        let gesture = LetterSwipeGesture(target: self, action: #selector(handleSwipe(_:)))
        gesture.delegate = self; gesture.cancelsTouchesInView = true
        gesture.delaysTouchesBegan = false; gesture.delaysTouchesEnded = false
        return gesture
    }()
    private let swipeTrail = CAShapeLayer()
    func cancelSwipe() {
        swipeGesture.isEnabled = false; swipeGesture.isEnabled = swipeEnabled
        swipeTrail.path = nil
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === cursorGesture {
            return cursorPadEnabled && !UIAccessibility.isVoiceOverRunning &&
                touch.view === spaceButton && canBeginCursorPad?() == true
        }
        guard !cursorPadActive, swipeEnabled, !symbols, !UIAccessibility.isVoiceOverRunning, canBeginSwipe?() == true else { return false }
        return (touch.view as? KeyButton)?.letter != nil
    }
    @objc private func handleSwipe(_ gesture: LetterSwipeGesture) {
        switch gesture.state {
        case .began:
            dismissKeyPreview(); onSwipeBegan?(); drawSwipe(gesture.samples)
        case .changed: drawSwipe(gesture.samples)
        case .ended:
            swipeTrail.path = nil
            guard let last = gesture.samples.last else { return }
            guard (hitTest(CGPoint(x: last.x, y: last.y), with: nil) as? KeyButton)?.letter != nil else { return }
            let width = max(1, letterKeys.first?.0.bounds.width ?? 35)
            let keys = letterKeys.map { button, letter -> SwipeKey in
                let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: self)
                return SwipeKey(letter: letter, x: center.x / width, y: center.y / width)
            }
            let samples = gesture.samples.map { SwipeSample(x: $0.x / width, y: $0.y / width, time: $0.time) }
            onSwipe?(samples, keys)
        case .cancelled, .failed: swipeTrail.path = nil
        default: break
        }
    }
    private func drawSwipe(_ samples: [SwipeSample]) {
        let path = UIBezierPath()
        for (index, sample) in samples.enumerated() {
            let point = CGPoint(x: sample.x, y: sample.y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        swipeTrail.path = path.cgPath
    }
    func showSwipeStatus(_ message: String) {
        candidateRow.arrangedSubviews.forEach { candidateRow.removeArrangedSubview($0); $0.removeFromSuperview() }
        let label = UILabel(); label.text = message; label.textAlignment = .center
        label.font = .systemFont(ofSize: 13); label.textColor = .secondaryLabel
        candidateRow.addArrangedSubview(label)
    }
    var onLetter: ((String, LetterTouch?) -> Void)?
    var prepareBackspace: (() -> (() -> Bool))?
    var onGeometryChanged: (() -> Void)?
    var calibrationAdjustment: ((String, String) -> Double)?
    private var portraitCalibration: Bool {
        window?.windowScene?.interfaceOrientation.isPortrait == true && !UIAccessibility.isVoiceOverRunning
    }
    var onAction: ((KeyAction) -> Void)?
    var onRemoveCandidate: ((String) -> Void)?
    var onCandidate: ((String) -> Void)?
    var onShiftLock: (() -> Void)?
    let globeButton = UIButton(type: .system)
    private let candidateRow = UIStackView()
    private let rows = UIStackView()
    private var letterKeys: [(UIButton, String)] = []
    private var shiftButton: UIButton?
    private var symbols = false
    var nextLetterWeights: [String: Double] = [:] { didSet {
        if nextLetterWeights != oldValue { setNeedsLayout() }
    } }
    private let keyPreview = UILabel()
    private weak var previewKey: UIButton?
    private var previewDismissal: DispatchWorkItem?
    private var lastLayoutSize: CGSize = .zero
    var keyPreviewsEnabled = true { didSet { if !keyPreviewsEnabled { dismissKeyPreview() } } }

    func dismissKeyPreview() {
        previewDismissal?.cancel(); previewDismissal = nil
        previewKey = nil
        keyPreview.isHidden = true
    }
    private func showKeyPreview(for button: UIButton) {
        guard keyPreviewsEnabled, window != nil else { return }
        previewDismissal?.cancel(); previewDismissal = nil
        previewKey = button
        let keyFrame = button.convert(button.bounds, to: self)
        let width: CGFloat = min(58, bounds.width - 4)
        let height: CGFloat = 46
        let x = min(max(2, keyFrame.midX - width / 2), bounds.width - width - 2)
        // Top-row previews overlap suggestions, never extend out of our window
        // or require more keyboard height. Edge keys stay inside the screen.
        let y = max(2, keyFrame.minY - height + 10)
        keyPreview.frame = CGRect(x: x, y: y, width: width, height: height)
        keyPreview.text = button.title(for: .normal)
        keyPreview.isHidden = false
        bringSubviewToFront(keyPreview)
    }
    private func endKeyPreview(for button: UIButton, linger: Bool) {
        guard previewKey === button else { return }
        guard linger else { dismissKeyPreview(); return }
        let dismissal = DispatchWorkItem { [weak self, weak button] in
            guard let self, let button, self.previewKey === button else { return }
            self.dismissKeyPreview()
        }
        previewDismissal?.cancel()
        previewDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: dismissal)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { dismissKeyPreview(); cancelSwipe(); cancelCursorPad() }
    }
    private var deleteButton: BackspaceButton?
    var backspaceGuardEnabled = true { didSet { configureBackspace() } }
    var backspaceDelayMilliseconds = 120 { didSet { configureBackspace() } }
    func cancelPendingBackspace() { deleteButton?.cancelPendingPress() }
    private func configureBackspace() {
        deleteButton?.cancelPendingPress()
        deleteButton?.guardEnabled = backspaceGuardEnabled
        deleteButton?.holdDelay = Double(backspaceDelayMilliseconds) / 1000
        deleteButton?.accessibilityHint = backspaceGuardEnabled
            ? "Hold for \(backspaceDelayMilliseconds) milliseconds to delete one character."
            : "Deletes one character."
    }
    private func makeBackspace() -> UIButton {
        let button = BackspaceButton(type: .system)
        button.expandsTouchArea = false
        button.setTitle("⌫", for: .normal)
        button.accessibilityLabel = "Delete"
        style(button, special: true)
        button.onDelete = { [weak self] in self?.onAction?(.backspace) }
        button.prepareDelete = { [weak self] in self?.prepareBackspace?() ?? { false } }
        deleteButton = button
        configureBackspace()
        return button
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGray5
        let settingsButton = key("⚙", action: .settings, special: true, label: "Keyboard settings")
        settingsButton.titleLabel?.font = .systemFont(ofSize: 19)
        settingsButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let toolbar = UIStackView(arrangedSubviews: [candidateRow, settingsButton])
        toolbar.axis = .horizontal; toolbar.spacing = 6
        let stack = UIStackView(arrangedSubviews: [toolbar, rows])
        stack.axis = .vertical; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -2),
            candidateRow.heightAnchor.constraint(equalToConstant: 28)
        ])
        candidateRow.axis = .horizontal; candidateRow.distribution = .fillEqually; candidateRow.spacing = 4
        rows.axis = .vertical; rows.distribution = .fillEqually; rows.spacing = 6
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.accessibilityLabel = "Next keyboard; hold for keyboard list"
        style(globeButton, special: true)
        buildRows()
        keyPreview.backgroundColor = .secondarySystemGroupedBackground
        keyPreview.textColor = .label
        keyPreview.font = .systemFont(ofSize: 34, weight: .medium)
        keyPreview.textAlignment = .center
        keyPreview.layer.cornerRadius = 9
        keyPreview.layer.shadowColor = UIColor.black.cgColor
        keyPreview.layer.shadowOpacity = 0.25
        keyPreview.layer.shadowRadius = 3
        keyPreview.layer.shadowOffset = CGSize(width: 0, height: 2)
        keyPreview.isUserInteractionEnabled = false
        keyPreview.isAccessibilityElement = false
        keyPreview.isHidden = true
        addSubview(keyPreview)
        cursorOverlay.text = "←  Cursor  →\n↑ Previous line · Next line ↓"
        cursorOverlay.numberOfLines = 2; cursorOverlay.textAlignment = .center
        cursorOverlay.font = .systemFont(ofSize: 17, weight: .medium)
        cursorOverlay.textColor = .secondaryLabel
        cursorOverlay.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.85)
        cursorOverlay.layer.cornerRadius = 8; cursorOverlay.clipsToBounds = true
        cursorOverlay.isUserInteractionEnabled = false; cursorOverlay.isAccessibilityElement = false
        cursorOverlay.isHidden = true; addSubview(cursorOverlay)
        addGestureRecognizer(cursorGesture)
        addGestureRecognizer(swipeGesture)
        swipeTrail.strokeColor = UIColor.systemBlue.withAlphaComponent(0.65).cgColor
        swipeTrail.fillColor = UIColor.clear.cgColor; swipeTrail.lineWidth = 3
        swipeTrail.lineCap = .round; swipeTrail.lineJoin = .round
        layer.addSublayer(swipeTrail)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func style(_ button: UIButton, special: Bool = false) {
        button.backgroundColor = special ? .systemGray3 : .secondarySystemGroupedBackground
        button.tintColor = .label
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 21)
        button.layer.cornerRadius = 6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.16; button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0
        button.addAction(UIAction { [weak button] _ in button?.alpha = 0.55 }, for: .touchDown)
        button.addAction(UIAction { [weak self, weak button] _ in button?.alpha = 1; self?.setNeedsLayout() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    private func key(_ title: String, action: KeyAction, special: Bool = false, label: String? = nil) -> UIButton {
        let button = KeyButton(type: .system)
        if case .backspace = action { button.expandsTouchArea = false }
        button.setTitle(title, for: .normal); button.accessibilityLabel = label ?? title
        style(button, special: special)
        button.addAction(UIAction { [weak self, weak button] _ in
            if case .text(let text) = action, button?.letter != nil {
                let touch = button?.letterTouch
                button?.letterTouch = nil
                self?.onLetter?(text, touch)
            } else { self?.onAction?(action) }
        }, for: .touchUpInside)
        return button
    }
    private func row(_ buttons: [UIView]) {
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal; stack.spacing = 5; stack.distribution = .fillEqually
        rows.addArrangedSubview(stack)
    }
    private func textKeys(_ strings: [String]) -> [UIView] {
        strings.map { text in
            let button = key(text, action: .text(text))
            if !symbols {
                (button as? KeyButton)?.letter = text
                (button as? KeyButton)?.captureTouch = { [weak self, weak button] point in
                    guard let self, let button, self.portraitCalibration,
                          let row = button.superview as? UIStackView,
                          let index = row.arrangedSubviews.firstIndex(of: button) else { return nil }
                    let slots = row.arrangedSubviews
                    let x = button.convert(point, to: row).x
                    var boundaries: [BoundaryTouch] = []
                    for leftIndex in [index - 1, index] where leftIndex >= 0 && leftIndex + 1 < slots.count {
                        guard let left = slots[leftIndex] as? KeyButton, let right = slots[leftIndex + 1] as? KeyButton,
                              let leftLetter = left.letter, let rightLetter = right.letter else { continue }
                        let width = min(left.frame.width, right.frame.width)
                        guard width > 0 else { continue }
                        let midpoint = (left.frame.maxX + right.frame.minX) / 2
                        boundaries.append(BoundaryTouch(left: leftLetter, right: rightLetter, offset: Double((x - midpoint) / width)))
                    }
                    return LetterTouch(letter: text, boundaries: boundaries)
                }
            }
            letterKeys.append((button, text))
            button.addAction(UIAction { [weak self, weak button] _ in
                if let button { self?.showKeyPreview(for: button) }
            }, for: [.touchDown, .touchDragEnter])
            button.addAction(UIAction { [weak self, weak button] _ in
                if let button { self?.endKeyPreview(for: button, linger: false) }
            }, for: [.touchDragExit, .touchUpOutside, .touchCancel])
            button.addAction(UIAction { [weak self, weak button] _ in
                if let button { self?.endKeyPreview(for: button, linger: true) }
            }, for: .touchUpInside)
            return button
        }
    }
    private func buildRows() {
        cancelCursorPad()
        cancelSwipe()
        dismissKeyPreview()
        cancelPendingBackspace()
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        letterKeys = []; shiftButton = nil
        let top = symbols ? Array("1234567890").map(String.init) : Array("qwertyuiop").map(String.init)
        let middle = symbols ? ["-", "/", ":", ";", "(", ")", "$", "&", "@"] : Array("asdfghjkl").map(String.init)
        let bottom = symbols ? [".", ",", "?", "!", "'", "\"", "_"] : Array("zxcvbnm").map(String.init)
        row(textKeys(top))
        row(textKeys(middle))
        let shift = key("⇧", action: .shift, special: true, label: "Shift; hold for caps lock")
        shift.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(holdShift(_:))))
        shiftButton = shift
        row([shift] + textKeys(bottom) + [makeBackspace()])
        let mode = key(symbols ? "ABC" : "123", action: .symbols, special: true, label: "Letters or numbers and punctuation")
        mode.titleLabel?.font = .systemFont(ofSize: 15)
        let space = key("space", action: .text(" "), label: "Space")
        spaceButton = space
        space.accessibilityHint = "Tap for space. Hold or drag to move the cursor."
        space.titleLabel?.font = .systemFont(ofSize: 17)
        let enter = key("return", action: .text("\n"), special: true, label: "Return")
        enter.titleLabel?.font = .systemFont(ofSize: 15)
        let control = UIStackView(arrangedSubviews: [mode, globeButton, space, enter])
        control.axis = .horizontal; control.spacing = 5
        mode.widthAnchor.constraint(equalTo: control.widthAnchor, multiplier: 0.13).isActive = true
        globeButton.widthAnchor.constraint(equalTo: mode.widthAnchor).isActive = true
        enter.widthAnchor.constraint(equalTo: control.widthAnchor, multiplier: 0.16).isActive = true
        rows.addArrangedSubview(control)
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if lastLayoutSize != bounds.size { dismissKeyPreview(); cancelSwipe(); cancelCursorPad(); onGeometryChanged?(); lastLayoutSize = bounds.size }
        swipeGesture.threshold = max(24, (letterKeys.first?.0.bounds.width ?? 35) * 0.75)
        // Resolve nested stacks before assigning gap-free touch cells.
        rows.layoutIfNeeded()
        // Do not move a cell while a finger is held on any key. UIKit completes
        // tracking before the next layout pass after the final finger lifts.
        let tracking = rows.arrangedSubviews.compactMap { $0 as? UIStackView }
            .flatMap { $0.arrangedSubviews }.compactMap { $0 as? UIButton }.contains { $0.isTracking }
        guard !tracking else { return }
        let rowViews = rows.arrangedSubviews
        for (rowIndex, rowView) in rowViews.enumerated() {
            guard let row = rowView as? UIStackView else { continue }
            row.layoutIfNeeded()
            let top = rowIndex == 0 ? rows.bounds.minY
                : (rowViews[rowIndex - 1].frame.maxY + row.frame.minY) / 2
            let bottom = rowIndex == rowViews.count - 1 ? rows.bounds.maxY
                : (row.frame.maxY + rowViews[rowIndex + 1].frame.minY) / 2
            let slots = row.arrangedSubviews
            func boundary(_ left: UIView, _ right: UIView) -> CGFloat {
                let midpoint = (left.frame.maxX + right.frame.minX) / 2
                // Symbols and every control-key boundary stay exactly fixed.
                guard !UIAccessibility.isVoiceOverRunning, !symbols,
                      let leftLetter = (left as? KeyButton)?.letter,
                      let rightLetter = (right as? KeyButton)?.letter else { return midpoint }
                return CGFloat(KeyTargeting.boundary(leftEdge: Double(left.frame.maxX), rightEdge: Double(right.frame.minX),
                    leftWidth: Double(left.frame.width), rightWidth: Double(right.frame.width),
                    leftWeight: nextLetterWeights[leftLetter] ?? 0, rightWeight: nextLetterWeights[rightLetter] ?? 0,
                    calibration: portraitCalibration ? (calibrationAdjustment?(leftLetter, rightLetter) ?? 0) : 0))
            }
            for (index, slot) in slots.enumerated() {
                guard let button = slot as? KeyButton else { continue }
                guard button.expandsTouchArea else { button.touchBounds = nil; continue }
                // Backspace participates in boundaries but never expands its own
                // hit area; nearby letters cannot absorb the delete key itself.
                let left = index == 0 ? row.bounds.minX
                    : boundary(slots[index - 1], slot)
                let right = index == slots.count - 1 ? row.bounds.maxX
                    : boundary(slot, slots[index + 1])
                let cell = CGRect(x: left + row.frame.minX, y: top,
                                  width: right - left, height: bottom - top)
                button.touchBounds = button.convert(cell, from: rows)
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if cursorPadActive && bounds.contains(point) { return self }
        let original = super.hitTest(point, with: event)
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
              rows.bounds.contains(rows.convert(point, from: self)) else { return original }
        // UIStackView clips hit testing to its own row bounds, so route the narrow
        // vertical gaps here as well. UIButton uses the same expanded bounds when
        // deciding whether a touch ends inside; routing alone would lose releases.
        for case let row as UIStackView in rows.arrangedSubviews {
            for case let button as KeyButton in row.arrangedSubviews {
                if button.isEnabled, !button.isHidden, button.alpha > 0.01,
                   button.point(inside: button.convert(point, from: self), with: event) {
                    return button
                }
            }
        }
        return original
    }

    @objc private func holdShift(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onShiftLock?() }
    }
    func returnToLetters(after text: String) {
        guard symbols, KeyboardLayoutPolicy.returnsToLetters(after: text) else { return }
        symbols = false; buildRows()
    }
    func toggleSymbols() { symbols.toggle(); buildRows() }
    func render(shift: ShiftState, candidates: [String], needsGlobe: Bool) {
        // Keep space reserved when iOS supplies its own switch key.
        globeButton.isEnabled = needsGlobe; globeButton.alpha = needsGlobe ? 1 : 0
        for (button, text) in letterKeys {
            let title = shift == .off ? text : text.uppercased()
            button.setTitle(title, for: .normal); button.accessibilityLabel = title
        }
        shiftButton?.setTitle(shift == .locked ? "⇪" : "⇧", for: .normal)
        shiftButton?.backgroundColor = shift == .off ? .systemGray3 : .systemBlue
        shiftButton?.accessibilityValue = shift == .locked ? "Caps lock" : shift == .once ? "On" : "Off"
        if cursorPadActive { showSwipeStatus("Cursor control · release to type"); return }
        candidateRow.arrangedSubviews.forEach { candidateRow.removeArrangedSubview($0); $0.removeFromSuperview() }
        if candidates.isEmpty {
            let label = UILabel(); label.text = "JBoard · on device"; label.textAlignment = .center
            label.font = .systemFont(ofSize: 13); label.textColor = .secondaryLabel
            candidateRow.addArrangedSubview(label)
        } else {
            for candidate in candidates {
                let button = UIButton(type: .system)
                button.setTitle(candidate, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 17)
                button.titleLabel?.adjustsFontSizeToFitWidth = true
                button.accessibilityLabel = "Use candidate \(candidate)"
                button.accessibilityHint = "Touch and hold for suggestion options"
                button.menu = UIMenu(children: [UIAction(title: "Don’t suggest “\(candidate)”", image: UIImage(systemName: "eye.slash"), attributes: .destructive) { [weak self] _ in
                    self?.onRemoveCandidate?(candidate)
                }])
                // A tap still inserts; UIKit presents this menu only on a hold.
                button.showsMenuAsPrimaryAction = false
                button.addAction(UIAction { [weak self] _ in self?.onCandidate?(candidate) }, for: .touchUpInside)
                candidateRow.addArrangedSubview(button)
            }
        }
    }
}
