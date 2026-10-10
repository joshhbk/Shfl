import ShflCore
import SwiftUI

struct PlaybackCommands: Commands {
    let sessionHost: ListeningSessionHost
    let player: ShufflePlayer

    var body: some Commands {
        CommandMenu("Playback") {
            Button(player.playbackState.isPlaying ? "Pause" : "Play") {
                Task { await sessionHost.togglePlayback() }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(sessionHost.isStartingSession)

            Divider()

            Button("Previous") {
                Task { try? await player.restartOrSkipToPrevious() }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(player.activeSession == nil)

            Button("Next") {
                Task { try? await player.skipToNext() }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(player.activeSession == nil)

            Divider()

            Button("Shuffle Again") {
                Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(sessionHost.isStartingSession)
        }
    }
}
