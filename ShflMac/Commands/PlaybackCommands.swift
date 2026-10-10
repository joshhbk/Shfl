import ShflCore
import SwiftUI

struct PlaybackCommands: Commands {
    let sessionHost: ListeningSessionHost
    let player: ShufflePlayer

    var body: some Commands {
        CommandMenu("Playback") {
            // No Space equivalent here: MainSplitView handles Space so text fields keep it.
            Button(player.playbackState.isPlaying ? "Pause" : "Play") {
                Task { await sessionHost.togglePlayback() }
            }
            .disabled(sessionHost.isStartingSession)

            Divider()

            Button("Previous") {
                Task { await sessionHost.skipToPrevious() }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
            .disabled(!sessionHost.canSkip)

            Button("Next") {
                Task { await sessionHost.skipToNext() }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
            .disabled(!sessionHost.canSkip)

            Divider()

            Button("Shuffle Again") {
                Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(sessionHost.isStartingSession)
        }
    }
}
