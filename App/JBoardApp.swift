import SwiftUI

@main
struct JBoardApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var sample = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Your words. On your iPhone.", systemImage: "keyboard")
                    Text("JBoard is an English tap keyboard. Includes QWERTY, numbers, punctuation and an offline English dictionary with spelling suggestions.")
                }
                Section("Enable JBoard") {
                    Text("1. Open Settings → General → Keyboard → Keyboards → Add New Keyboard.")
                    Text("2. Choose JBoard.")
                    Text("3. In any supported text field, hold the globe key and choose JBoard.")
                    Text("Full Access is not required or requested.")
                        .foregroundStyle(.secondary)
                }
                Section("Try it here") {
                    TextEditor(text: $sample)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Keyboard test area")
                    Text("Tap Shift for one capital; hold Shift for caps lock. Tap 123 for numbers and punctuation. Candidates replace the current word only when you tap one.")
                        .font(.footnote)
                }
                Section("Keyboard settings & dictionary") {
                    Text("Tap ⚙ on JBoard to toggle suggestions, explicitly save the current word, or clear your saved dictionary.")
                    Text("Settings and saved words stay in the keyboard’s own storage. This host app does not share or edit that storage. Text in the test area is not saved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Dictionary") {
                    NavigationLink("Dictionary credits & licenses") {
                        ScrollView {
                            Text((Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
                                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "Dictionary notices unavailable")
                                .font(.footnote).textSelection(.enabled).padding()
                        }.navigationTitle("Dictionary credits")
                    }
                    Text("The dictionary contains 82,834 words, ranked by frequency. Suggestions handle one missing, extra, wrong or swapped letter, including in unfinished words. After a space, local word-pair frequencies and words you type suggest the next word. The keyboard settings let you stop learning or clear learned predictions. Tap to accept and add a trailing space. Or swipe across a word and lift: choose an alternative in the bar if needed. The first backspace undoes the whole swiped word. Swipe typing can be disabled in keyboard settings.")
                    Text("iOS uses its own keyboard for passwords and some phone-number fields. Apps can also disallow custom keyboards.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("JBoard")
        }
    }
}
