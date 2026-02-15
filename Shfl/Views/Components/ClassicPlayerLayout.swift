import SwiftUI

/// The classic iPod Shuffle player layout, composing PlayerTopBar, SongInfoDisplay, and PlayerControlsPanel
struct ClassicPlayerLayout: View {
    let playbackState: PlaybackState
    let hasSongs: Bool
    let isControlsDisabled: Bool
    let progressState: PlayerProgressState?
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onShuffle: () -> Void
    let isShuffling: Bool
    let showError: Bool
    let errorMessage: String
    let safeAreaInsets: EdgeInsets
    let onDismissError: () -> Void

    /// Returns the song only if actively playing or paused (not during loading)
    private var playingOrPausedSong: Song? {
        switch playbackState {
        case .playing(let song), .paused(let song):
            return song
        default:
            return nil
        }
    }

    /// Coarse state category for animating layout transitions between empty/loading/active
    private var stateCategory: Int {
        switch playbackState {
        case .playing, .paused: return 2
        case .loading: return 1
        default: return 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showError {
                ErrorBanner(message: errorMessage, onDismiss: onDismissError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            PlayerTopBar(
                onAddTapped: onAdd,
                onSettingsTapped: onSettings,
                topPadding: showError ? 16 : safeAreaInsets.top + 16
            )

            Spacer()

            // Album art card - show real art when playing/paused, placeholder otherwise
            ZStack {
                AlbumArtCard(artworkURL: playingOrPausedSong?.artworkURL, size: 280)
                    .id(playingOrPausedSong?.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            .animation(.easeInOut(duration: 0.4), value: playingOrPausedSong?.id)
            .padding(.bottom, 16)
            .opacity(hasSongs || playbackState.isActive ? 1 : 0)

            // Song info - floating directly on background
            SongInfoDisplay(
                playbackState: playbackState,
                hasSongs: hasSongs,
                progressState: progressState,
                onSeek: onSeek,
                onAddSongs: onAdd,
                onShuffle: onShuffle,
                isShuffling: isShuffling
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 20)

            // Click wheel - floating with shadow
            ClickWheelView(
                isPlaying: playbackState.isPlaying,
                onPlayPause: onPlayPause,
                onSkipForward: onSkipForward,
                onSkipBack: onSkipBack,
                onVolumeUp: { VolumeController.increaseVolume() },
                onVolumeDown: { VolumeController.decreaseVolume() },
                scale: 0.75
            )
            .disabled(isControlsDisabled)
            .opacity(isControlsDisabled ? 0.6 : 1.0)
            .padding(.bottom, safeAreaInsets.bottom + 20)
        }
        .animation(.easeInOut(duration: 0.3), value: stateCategory)
        .animation(.easeInOut(duration: 0.2), value: showError)
    }
}
