import UIKit

final class KeyboardViewController: UIInputViewController {
    private let swipeQueue = DispatchQueue(label: "JBoard.swipe", qos: .userInitiated)
    // Accessed only on swipeQueue.
    private var swipeDecoder: LocalSwipeDecoder?
    private var swipeGeneration = 0
    private var swipeStartedGeneration: Int?
    private var lastDocumentID: UUID?
    private var swipeContext: DeletionContext?
    private let touchCalibration = TouchCalibration()
    private let settings = KeyboardSettings()
    private let exclusions = SuggestionExclusions()
    private lazy var learnedPairs = LearnedWordPairs(exclusions: exclusions)
    private let dictionary = PersonalDictionary()
    private let lexicon = BundledLexicon()
    private var controller: InputController!
    private let keyboard = KeyboardView()
    private var settingsPanel: UIView?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Unowned is safe: this adapter is retained only by this controller's input engine.
        let document = ProxyDocument { [unowned self] in self.textDocumentProxy }
        controller = InputController(document: document,
            candidates: CandidateService(lexicons: [lexicon, dictionary], nextWords: .bundled, learnedPairs: learnedPairs, exclusions: exclusions), settings: settings, learnedPairs: learnedPairs, touchCalibration: touchCalibration)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 244)
        heightConstraint?.priority = .init(999)
        heightConstraint?.isActive = true
        keyboard.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        applyBackspaceSettings()
        keyboard.keyPreviewsEnabled = settings.keyPreviewsEnabled
        keyboard.prepareBackspace = { [weak self] in
            guard let self, let context = self.deletionContext else { return { false } }
            return { [weak self] in self?.deletionContext == context }
        }
        keyboard.onAction = { [weak self] action in self?.handle(action) }
        keyboard.swipeEnabled = settings.swipeEnabled
        keyboard.canBeginSwipe = { [weak self] in
            self?.currentDocumentID != nil && self?.controller.canInsertSwipe == true
        }
        keyboard.onSwipeBegan = { [weak self] in
            guard let self else { return }
            self.swipeGeneration += 1; self.swipeStartedGeneration = self.swipeGeneration
            self.swipeContext = self.deletionContext
            self.controller.resetTouchCalibrationSession()
        }
        keyboard.onSwipe = { [weak self] samples, keys in self?.decodeSwipe(samples, keys: keys) }
        swipeQueue.async { [weak self] in self?.swipeDecoder = LocalSwipeDecoder(words: BundledLexicon().swipeWords) }
        keyboard.onLetter = { [weak self] text, touch in
            self?.swipeGeneration += 1; self?.controller.type(text, touch: touch); self?.render()
        }
        keyboard.onGeometryChanged = { [weak self] in
            self?.swipeGeneration += 1; self?.controller?.resetTouchCalibrationSession()
        }
        keyboard.calibrationAdjustment = { [weak self] left, right in
            guard let self, self.settings.touchCalibrationEnabled else { return 0 }
            return self.touchCalibration.adjustment(left: left, right: right)
        }
        keyboard.onCandidate = { [weak self] word in
            self?.swipeGeneration += 1; self?.controller.accept(word); self?.render()
        }
        keyboard.onRemoveCandidate = { [weak self] word in
            guard let self else { return }
            self.exclusions.hide(word)
            self.learnedPairs.remove(word)
            self.dictionary.remove(word)
            self.controller.resetLearningSession()
            self.refresh()
        }
        keyboard.onShiftLock = { [weak self] in self?.swipeGeneration += 1; self?.controller.lockShift(); self?.render() }
        refresh()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let compact = view.bounds.width > 600
        let height: CGFloat = (compact ? 214 : 244) + view.safeAreaInsets.bottom
        if heightConstraint?.constant != height { heightConstraint?.constant = height }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refresh() }
    override func viewWillDisappear(_ animated: Bool) {
        swipeGeneration += 1; keyboard.cancelSwipe(); controller?.clearSwipeReplacement()
        keyboard.cancelPendingBackspace()
        keyboard.dismissKeyPreview()
        controller?.resetTouchCalibrationSession()
        controller?.resetLearningSession()
        super.viewWillDisappear(animated)
    }
    override func textWillChange(_ textInput: UITextInput?) {
        // Notes may send notifications without moving the cursor. Validate the
        // captured field/context at deletion time instead of canceling every hold.
        keyboard.dismissKeyPreview()
        controller?.resetTouchCalibrationSession()
        controller?.resetLearningSession()
        // A candidate must not survive a host selection/cursor change.
        settingsPanel?.removeFromSuperview(); settingsPanel = nil
    }
    override func textDidChange(_ textInput: UITextInput?) { refresh() }
    override func selectionDidChange(_ textInput: UITextInput?) { refresh() }
    private func decodeSwipe(_ samples: [SwipeSample], keys: [SwipeKey]) {
        guard let context = swipeContext, context == deletionContext, swipeStartedGeneration == swipeGeneration,
              settings.swipeEnabled else { return }
        let generation = swipeGeneration
        let personal = dictionary.words
        let preferred = CandidateService(lexicons: [], nextWords: .bundled, learnedPairs: learnedPairs)
            .nextWordCandidates(after: context.before ?? "")
        keyboard.showSwipeStatus("Reading swipe…")
        swipeQueue.async { [weak self] in
            guard let self else { return }
            let words = self.swipeDecoder?.decode(samples: samples, keys: keys, preferred: preferred, personal: personal) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self, self.swipeGeneration == generation, self.deletionContext == context,
                      self.settings.swipeEnabled else { return }
                if self.controller.insertSwipe(words) { self.render() }
                else { self.keyboard.showSwipeStatus("No match — try again") }
            }
        }
    }
    private var currentDocumentID: UUID? {
        guard let proxy = textDocumentProxy as? NSObject else { return nil }
        return DocumentIdentity.read(from: proxy)
    }
    private var deletionContext: DeletionContext? {
        guard let id = currentDocumentID else { return nil }
        return DeletionContext(documentID: id,
            before: textDocumentProxy.documentContextBeforeInput,
            after: textDocumentProxy.documentContextAfterInput,
            selection: textDocumentProxy.selectedText)
    }
    private func handle(_ action: KeyAction) {
        swipeGeneration += 1
        switch action {
        case .text(let text): controller.type(text); keyboard.returnToLetters(after: text)
        case .backspace: controller.backspace()
        case .shift: controller.toggleShift()
        case .symbols: keyboard.toggleSymbols()
        case .settings: showSettings()
        }
        render()
    }
    private func refresh() {
        let id = currentDocumentID
        if let lastDocumentID, lastDocumentID != id {
            swipeGeneration += 1; keyboard.cancelSwipe(); controller?.clearSwipeReplacement()
        }
        lastDocumentID = id
        controller?.refresh(); render()
    }
    private func render() {
        guard let controller else { return }
        keyboard.setNeedsLayout()
        keyboard.nextLetterWeights = controller.nextLetterWeights
        keyboard.render(shift: controller.shift, candidates: controller.candidates, needsGlobe: needsInputModeSwitchKey)
    }
    private func applyBackspaceSettings() {
        keyboard.backspaceGuardEnabled = settings.backspaceGuardEnabled
        keyboard.backspaceDelayMilliseconds = settings.backspaceDelayMilliseconds
    }
    private func showSettings() {
        guard settingsPanel == nil else { return }
        keyboard.cancelPendingBackspace()
        keyboard.dismissKeyPreview()
        let panel = UIView(); panel.backgroundColor = .systemGroupedBackground
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel); settingsPanel = panel
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor), panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let title = UILabel(); title.text = "JBoard settings"; title.font = .boldSystemFont(ofSize: 18)
        let toggle = UISwitch(); toggle.isOn = settings.candidatesEnabled
        toggle.addAction(UIAction { [weak self, weak toggle] _ in
            self?.settings.candidatesEnabled = toggle?.isOn ?? true; self?.refresh()
        }, for: .valueChanged)
        let label = UILabel(); label.text = "Show suggestions"
        let option = UIStackView(arrangedSubviews: [label, toggle]); option.spacing = 10
        func button(_ title: String, action: @escaping () -> Void) -> UIButton {
            let result = UIButton(type: .system); result.setTitle(title, for: .normal)
            result.addAction(UIAction { _ in action() }, for: .touchUpInside)
            result.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
            return result
        }
        let word = controller.currentWord
        let save = button(word.isEmpty ? "Type a word to save it" : "Save “\(word)” to dictionary") { [weak self] in
            self?.dictionary.add(word); self?.closeSettings()
        }
        save.isEnabled = !word.isEmpty
        let clear = button("Clear personal dictionary") { [weak self] in self?.dictionary.removeAll(); self?.closeSettings() }
        let done = button("Done") { [weak self] in self?.closeSettings() }
        let guardToggle = UISwitch(); guardToggle.isOn = settings.backspaceGuardEnabled
        let guardLabel = UILabel(); guardLabel.text = "Backspace guard"
        let guardRow = UIStackView(arrangedSubviews: [guardLabel, guardToggle]); guardRow.spacing = 10
        let delayLabel = UILabel()
        delayLabel.text = "Hold: \(settings.backspaceDelayMilliseconds) ms"
        let delay = UIStepper(); delay.minimumValue = 80; delay.maximumValue = 180; delay.stepValue = 20
        delay.value = Double(settings.backspaceDelayMilliseconds)
        delay.isEnabled = settings.backspaceGuardEnabled
        delay.accessibilityLabel = "Backspace hold delay in milliseconds"
        delay.accessibilityValue = "\(settings.backspaceDelayMilliseconds)"
        guardToggle.addAction(UIAction { [weak self, weak guardToggle, weak delay] _ in
            guard let self else { return }
            self.settings.backspaceGuardEnabled = guardToggle?.isOn ?? true
            delay?.isEnabled = self.settings.backspaceGuardEnabled
            self.applyBackspaceSettings()
        }, for: .valueChanged)
        delay.addAction(UIAction { [weak self, weak delay, weak delayLabel] _ in
            guard let self, let delay else { return }
            self.settings.backspaceDelayMilliseconds = Int(delay.value)
            delayLabel?.text = "Hold: \(self.settings.backspaceDelayMilliseconds) ms"
            delay.accessibilityValue = "\(self.settings.backspaceDelayMilliseconds)"
            self.applyBackspaceSettings()
        }, for: .valueChanged)
        let delayRow = UIStackView(arrangedSubviews: [delayLabel, delay]); delayRow.spacing = 10
        // Keep Done visible; the settings body scrolls at the compact keyboard height.
        let header = UIStackView(arrangedSubviews: [title, done]); header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        let previewsToggle = UISwitch(); previewsToggle.isOn = settings.keyPreviewsEnabled
        let previewsLabel = UILabel(); previewsLabel.text = "Key popups"
        let previewsRow = UIStackView(arrangedSubviews: [previewsLabel, previewsToggle]); previewsRow.spacing = 10
        previewsToggle.addAction(UIAction { [weak self, weak previewsToggle] _ in
            guard let self else { return }
            self.settings.keyPreviewsEnabled = previewsToggle?.isOn ?? true
            self.keyboard.keyPreviewsEnabled = self.settings.keyPreviewsEnabled
        }, for: .valueChanged)
        let learningToggle = UISwitch(); learningToggle.isOn = settings.wordLearningEnabled
        let learningLabel = UILabel(); learningLabel.text = "Learn word pairs"
        let learningRow = UIStackView(arrangedSubviews: [learningLabel, learningToggle]); learningRow.spacing = 10
        learningToggle.addAction(UIAction { [weak self, weak learningToggle] _ in
            self?.settings.wordLearningEnabled = learningToggle?.isOn ?? true
            self?.controller.resetLearningSession()
        }, for: .valueChanged)
        let clearLearning = button("Clear learned predictions (\(learnedPairs.count))") { [weak self] in
            self?.learnedPairs.removeAll(); self?.controller.resetLearningSession(); self?.closeSettings()
        }
        let restoreSuggestions = button("Restore hidden suggestions (\(exclusions.count))") { [weak self] in
            self?.exclusions.removeAll(); self?.closeSettings()
        }
        restoreSuggestions.isEnabled = exclusions.count > 0
        let targetsToggle = UISwitch(); targetsToggle.isOn = settings.dynamicKeyTargetsEnabled
        let targetsLabel = UILabel(); targetsLabel.text = "Dynamic key targets"
        let targetsRow = UIStackView(arrangedSubviews: [targetsLabel, targetsToggle]); targetsRow.spacing = 10
        targetsToggle.addAction(UIAction { [weak self, weak targetsToggle] _ in
            self?.settings.dynamicKeyTargetsEnabled = targetsToggle?.isOn ?? true
            self?.refresh()
        }, for: .valueChanged)
        let calibrationToggle = UISwitch(); calibrationToggle.isOn = settings.touchCalibrationEnabled
        let calibrationLabel = UILabel(); calibrationLabel.text = "Learn my taps (portrait)"
        let calibrationRow = UIStackView(arrangedSubviews: [calibrationLabel, calibrationToggle]); calibrationRow.spacing = 10
        calibrationToggle.addAction(UIAction { [weak self, weak calibrationToggle] _ in
            self?.settings.touchCalibrationEnabled = calibrationToggle?.isOn ?? true
            self?.controller.resetTouchCalibrationSession(); self?.refresh()
        }, for: .valueChanged)
        let resetCalibration = button("Reset tap calibration") { [weak self] in
            self?.touchCalibration.reset(); self?.controller.resetTouchCalibrationSession(); self?.closeSettings()
        }
        let swipeToggle = UISwitch(); swipeToggle.isOn = settings.swipeEnabled
        let swipeLabel = UILabel(); swipeLabel.text = "Swipe typing"
        let swipeRow = UIStackView(arrangedSubviews: [swipeLabel, swipeToggle]); swipeRow.spacing = 10
        swipeToggle.addAction(UIAction { [weak self, weak swipeToggle] _ in
            guard let self else { return }
            self.settings.swipeEnabled = swipeToggle?.isOn ?? true
            self.swipeGeneration += 1; self.keyboard.swipeEnabled = self.settings.swipeEnabled
            self.keyboard.cancelSwipe(); self.controller.clearSwipeReplacement(); self.refresh()
        }, for: .valueChanged)
        let dictionaryStatus = UILabel()
        dictionaryStatus.text = lexicon.isFallback ? "Dictionary unavailable — using fallback words" : "English dictionary: \(lexicon.count.formatted()) words · offline"
        dictionaryStatus.font = .systemFont(ofSize: 12)
        dictionaryStatus.textColor = .secondaryLabel
        dictionaryStatus.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [guardRow, delayRow, swipeRow, previewsRow, targetsRow, calibrationRow, resetCalibration, option, learningRow, clearLearning, restoreSuggestions, dictionaryStatus, save, clear])
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(header); panel.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }
    private func closeSettings() { settingsPanel?.removeFromSuperview(); settingsPanel = nil; refresh() }
}
