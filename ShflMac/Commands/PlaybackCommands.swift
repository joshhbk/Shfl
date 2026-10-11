import ShflCore
import SwiftUI

struct PlaybackCommands: Commands {
    let sessionHost: ListeningSessionHost

    // ⌘← and ⌘→ move the caret in text fields, and menu equivalents win over the field.
    @FocusedValue(\.isEditingText) private var isEditingText
    @FocusedValue(\.wholeSession) private var wholeSession

    var body: some Commands {
        CommandMenu("Playback") {
            // No Space equivalent here: MainSplitView handles Space so text fields keep it.
            Button(sessionHost.intents.play.title) {
                Task { await sessionHost.togglePlayback() }
            }
            .disabled(sessionHost.isStartingSession)

            Divider()

            Button("Next") {
                Task { await sessionHost.skipToNext() }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!sessionHost.canSkip || isEditingText == true)

            Button("Previous") {
                Task { await sessionHost.skipToPrevious() }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!sessionHost.canSkip || isEditingText == true)

            Divider()

            Button(sessionHost.intents.shuffle.title) {
                Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(sessionHost.isStartingSession)
        }

        CommandGroup(after: .sidebar) {
            Button(wholeSession?.wrappedValue == true ? "Show Artwork" : "Show Whole Session") {
                wholeSession?.wrappedValue.toggle()
            }
            .keyboardShortcut("u", modifiers: [.option, .command])
            .disabled(wholeSession == nil || sessionHost.timeline.status == .idle)
        }
    }
}
