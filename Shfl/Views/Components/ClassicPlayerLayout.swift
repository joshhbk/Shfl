import SwiftUI

/// The classic iPod Shuffle player layout, composing PlayerTopBar, SongInfoDisplay, and PlayerControlsPanel
struct ClassicPlayerLayout: View {
    let playbackState: PlaybackState
    let isControlsDisabled: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let actions: PlayerActions
    let showError: Bool
    let errorMessage: String
    let safeAreaInsets: EdgeInsets
    let onDismissError: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showError {
                ErrorBanner(message: errorMessage, onDismiss: onDismissError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            PlayerTopBar(
                onAddTapped: actions.onAdd,
                onSettingsTapped: actions.onSettings,
                topPadding: showError ? 16 : safeAreaInsets.top + 16
            )

            Spacer()

            // Album art card - only show when there's a song
            if let song = playbackState.currentSong {
                AlbumArtCard(artworkURL: song.artworkURL, size: 320)
                    .padding(.bottom, 24)
            }

            // Song info - floating directly on background
            SongInfoDisplay(
                playbackState: playbackState,
                currentTime: currentTime,
                duration: duration,
                onSeek: actions.onSeek
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 20)

            // Click wheel - floating with shadow
            ClickWheelView(
                isPlaying: playbackState.isPlaying,
                onPlayPause: actions.onPlayPause,
                onSkipForward: actions.onSkipForward,
                onSkipBack: actions.onSkipBack,
                onVolumeUp: { VolumeController.increaseVolume() },
                onVolumeDown: { VolumeController.decreaseVolume() },
                scale: 0.6
            )
            .disabled(isControlsDisabled)
            .opacity(isControlsDisabled ? 0.6 : 1.0)
            .padding(.bottom, safeAreaInsets.bottom + 20)
        }
        .animation(.easeInOut(duration: 0.2), value: showError)
    }
}
