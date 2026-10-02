# JBoard

An experimental iPhone keyboard built in Swift, with a SwiftUI host app and UIKit Custom Keyboard extension. Tap and swipe typing, suggestions, and personal learning run entirely on-device. **No Full Access, runtime network calls, third-party runtime dependencies, or App Groups.**

This is a working prototype developed through physical-iPhone feedback, not an App Store release or a replacement for a mature keyboard engine. Contributions and reproducible bug reports are welcome.

## Features

- English QWERTY tap typing, Shift/caps lock, numbers and punctuation, space, return, and Apple's next-keyboard/globe control.
- Gap-free letter touch targets and key popups, with a compact suggestion bar.
- Adjustable backspace guard (80–180 ms, default 120 ms). A short hold deletes once; minor drift is tolerated after the press starts. Held-key repeat is not implemented.
- An 82,834-word frequency dictionary, one-edit typo correction, and typo-tolerant completion: `woeki` → `working`.
- Offline next-word suggestions, explicitly saved personal words, and optional learning from typed word pairs.
- Long-press a suggestion and choose **Don’t suggest** to remove its saved entries and prevent future suggestions or relearning. **Restore hidden suggestions** clears the exclusion list.
- Experimental swipe typing with a visible trail, ranked alternatives, automatic spacing, and whole-word undo.
- Optional dynamic key targets based on likely next letters. Separate portrait touch calibration learns small boundary adjustments from explicit corrections; calibration is off by default.

## Build and install

1. Install the full **Xcode** app with iOS platform support and an SDK that supports your iPhone. Minimum deployment target: **iOS 16**, iPhone only.
2. Open **JBoard.xcodeproj**, not Package.swift. Select the **JBoard** scheme.
3. Add your Apple account in Xcode → Settings → Accounts. For both targets, keep automatic signing and select your Team. Alternatively, copy `LocalSigning.xcconfig.example` to `LocalSigning.xcconfig` and supply your development-team ID. The local file is ignored by Git.
4. Set `JBOARD_HOST_BUNDLE_IDENTIFIER` in `LocalSigning.xcconfig` (or edit both targets in Xcode) to identifiers you control:
   - Host: `com.example.JBoard`
   - Extension: `com.example.JBoard.Keyboard`
   Keep the extension identifier prefixed with the host identifier. No extra entitlements are required.
5. Connect and unlock your iPhone, trust the Mac if prompted, and enable Developer Mode under Settings → Privacy & Security when required. Select the phone and press **Run**. The host builds and embeds the extension.
6. On iPhone, open **Settings → General → Keyboard → Keyboards → Add New Keyboard → JBoard**. Full Access is not requested.
7. Open Notes or the host app's test field. Hold the globe and select JBoard.

Personal Team provisioning can require periodic rebuilding. After changing bundle IDs, remove stale JBoard entries from the keyboard list if needed. If a newly installed update is not visible, switch keyboards and back.

## Using the keyboard

Tap Shift for one capital; hold it for caps lock. Shift also capitalizes the visible suggestions: type or swipe a word, tap Shift, then choose its capitalized suggestion. Hold Shift for ALL CAPS. This also works for next-word predictions; text changes only when you select a suggestion. **123 / ABC** changes layouts. `. , ? ! ; :` and Return switch back to letters. Apostrophes, hyphens, slashes, numbers, and spaces keep the symbol layout.

The candidate bar keeps the typed word first and offers ranked completions/corrections. Choosing a candidate finishes the word and adds a space at the end of the document. Existing following whitespace or punctuation is preserved. Tap typing does not silently autocorrect.

Open **⚙** for suggestions, key popups, backspace timing, personal words, learning, dynamic targets, calibration, and swipe settings. Settings live in the keyboard extension; the host app explains them but does not share their storage.

### Swipe typing

Swipe through an English word and lift on its final letter. Start at a word boundary, or directly after tapping a complete dictionary word (including `a` and `I`): a successful swipe adds the separating space automatically. You do not need to select the already-correct typed word first. Repeated letters need no special loop; type single-letter words, contractions, punctuation, and unsupported names normally. Saved alphabetic personal words participate in swipe recognition.

The best match is inserted with a trailing space. Tap an alternative to replace it. The first backspace removes the whole swiped word and its space; after tapping resumes, backspace returns to single-character deletion. Punctuation removes the automatic space before it. Consecutive swipes are already separated by spaces.

Decoding runs on a background queue. A new keyboard action or changed field/cursor invalidates pending results. Swipe guesses do not automatically train word-pair history or tap calibration. **Swipe typing** is on by default and can be turned off. VoiceOver uses normal key activation.

### Learning and touch targets

**Learn word pairs** is on by default. It records completed pairs entered through JBoard, capped at 5,000 pairs. Existing documents are not scanned. Turning learning off stops recording but retains predictions; **Clear learned predictions** removes the history. Editing, navigation, and sentence boundaries break the learning chain. Previously learned pairs are not retroactively removed by subsequent edits.

**Dynamic key targets** is on by default. It adjusts invisible horizontal boundaries according to dictionary prefix frequencies, by at most 12% of the narrower key width. Visible keys, centers, row boundaries, and control keys stay fixed. Unknown prefixes and VoiceOver use normal targets.

**Learn my taps (portrait)** is off by default. Only explicit single-letter corrections between horizontal neighbors, with a tap near their shared edge, qualify. Five observations are required before movement begins; the effect grows gradually through twenty. Calibration is bounded at 12% of key width; combined calibration and dynamic adjustments are capped at 18%. Landscape and VoiceOver do not capture or apply calibration. **Reset tap calibration** erases the estimates. Switching it off disables learning and application while retaining estimates.

## Privacy

`RequestsOpenAccess` is false. The keyboard contains no runtime networking or analytics code. Its local UserDefaults store preferences, explicitly saved words, learned word pairs, hidden suggestions, and aggregate calibration estimates. Raw touch paths and per-word calibration evidence are transient and are not saved. Host test-field text stays in memory. Data-clear controls are available in the keyboard settings.

UserDefaults usage is declared in the extension's privacy manifest. Local signing overrides, Xcode user state, build outputs, certificates, and provisioning profiles are excluded from Git.

## Architecture

| Area | Responsibility |
| --- | --- |
| `App/` | SwiftUI setup guide, unsaved test field, dictionary credits |
| `Keyboard/KeyboardView.swift` | UIKit keys, touch routing, swipe capture/trail, candidate menus |
| `Keyboard/KeyboardViewController.swift` | Extension lifecycle, settings, background decoding and context validation |
| `Keyboard/ProxyDocument.swift` | Live `UITextDocumentProxy` adapter |
| `Core/InputController.swift` | Shift, insertion/deletion, candidates, learning boundaries and swipe replacement |
| `Core/Lexicon.swift` | Frequency dictionary, bounded typo/prefix lookup and personal words |
| `Core/Candidates.swift` | Ranking, next-word prediction, local pair learning and exclusions |
| `Core/KeyTargeting.swift` | Bounded target geometry and portrait calibration |
| `Core/SwipeDecoder.swift` | Endpoint pruning, spatial resampling and banded path matching |
| `Core/Settings.swift` | Extension-local preferences |
| `Core/Resources/` | English frequency data, word-pair data, third-party notices |
| `Tests/CoreTests/` | Portable Swift package tests with a mock document |

Core files compile directly into the extension. `Package.swift` tests the same code independently; the Xcode project has no external package dependencies.

## Validation

Run the core suite from the project directory:

```sh
swift test
```

With full Xcode selected, compile both iOS targets without signing:

```sh
xcodebuild -project JBoard.xcodeproj -scheme JBoard \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

If Terminal selects Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The limited fallback `./Scripts/check-core.sh` runs 18 input/backspace/preference checks; resource-backed integration tests require `swift test`.

Current baseline: **114 core tests pass**. The app and extension build, sign, and install on a physical iPhone 14 using Xcode 27. Tap typing and responsiveness have received physical-phone feedback. Synthetic swipe tests recognize hello, water, working, keyboard, tomorrow, thank, and nitrification, including slightly offset paths; this does not establish real-finger swipe accuracy. Comprehensive visual, accessibility, and device-matrix testing remains outstanding.

Useful phone checks: type `woeki` and choose `working`; type `aeration basin ` and check learned next-word suggestions; hide and restore a suggestion; move the cursor before choosing a candidate; swipe a word, choose an alternative, and undo it. Check light/dark mode and VoiceOver. iOS may substitute its own keyboard in secure or phone-pad fields, and apps can disallow custom keyboards.

## Limitations

English only. The dictionary and word-pair data are not a sentence-level language model. Typo repair supports one edit; multi-error input needs further work. Swipe recognition is an initial shape matcher. No automatic sentence capitalization, held-delete repeat, keyboard-type-specific layouts, or production app icon yet. Return inserts a newline; the host app decides how to interpret it. iOS can limit document context, which constrains prediction and replacement.

## License and dictionary attribution

Original JBoard code is available under the [MIT License](LICENSE). The bundled dictionary data has separate upstream terms described in [ThirdPartyNotices.txt](Core/Resources/ThirdPartyNotices.txt); the code license does not replace those terms.

The English dictionary and word pairs derive from [Wolf Garbe’s SymSpell](https://github.com/wolfgarbe/SymSpell), revision `c239062ae02961df18ab7da1671d01b4388204e0`, combining Google Books Ngram frequencies and SCOWL vocabulary. The frequency list retains 82,834 entries and counts. The next-word table retains three ranked continuations per known word: 35,972 pairs across 16,600 contexts. The notices include source links, checksums, transformations, SymSpell's MIT license, Google Books CC BY 3.0 attribution, and full SCOWL source notices. They are bundled with the app and accessible under **Dictionary credits & licenses**.

## Contributing

Bug reports should include the iPhone/iOS version, the relevant keyboard settings, and a short reproducible typing sequence using non-sensitive example text. For swipe problems, report the intended word and the alternatives shown. Run `swift test` and an unsigned iOS build before proposing code changes. Do not commit local signing files, profiles, keys, or personal typing history.


## Spacebar trackpad

Tap Space normally to insert a space. Hold it for 300 ms, or drag at least 12 points from it, to turn the keyboard into a cursor pad. Continue dragging anywhere over the keys; release to return to typing. Left/right moves by characters. Up/down moves between explicit newline-separated lines while preserving the character column where possible; **it cannot follow visual line wrapping**, because the custom-keyboard proxy exposes character offsets, not the host's text layout. Movement is limited by the context the host supplies. Selection extension is not implemented. This feature is on by default under **Spacebar trackpad** and is disabled during VoiceOver navigation. Cursor gestures do not insert text, train predictions, or persist touch history.

The supported movement API is Apple's [adjustTextPosition(byCharacterOffset:)](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/adjusttextposition(bycharacteroffset:)). Device testing across host apps remains necessary, especially for rich-text or web editors.
