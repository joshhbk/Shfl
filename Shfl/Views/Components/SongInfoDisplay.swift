import SwiftUI

/// Displays song title, artist, and optional progress bar based on playback state
struct SongInfoDisplay: View {
    @Environment(\.shuffleTheme) private var theme

    let playbackState: PlaybackState
    let hasSongs: Bool
    let progressState: PlayerProgressState?
    let onSeek: (TimeInterval) -> Void
    let isShuffling: Bool

    init(
        playbackState: PlaybackState,
        hasSongs: Bool = false,
        progressState: PlayerProgressState? = nil,
        onSeek: @escaping (TimeInterval) -> Void = { _ in },
        isShuffling: Bool = false
    ) {
        self.playbackState = playbackState
        self.hasSongs = hasSongs
        self.progressState = progressState
        self.onSeek = onSeek
        self.isShuffling = isShuffling
    }

    var body: some View {
        ZStack {
            // Hidden reference matching active content layout — reserves consistent height
            activeHeightReference
                .hidden()

            // Single transition point: "is there a song to display?"
            // Switching on currentSong (instead of per-branch on playbackState) keeps
            // the view stable across loading → playing and empty → loading(shuffle),
            // so we only cross-fade once per user-visible state change.
            if let song = displayedSong {
                activeContent(song: song)
                    .transition(.opacity)
            } else {
                EmptyPlayerContent(variant: emptyVariant, animateEntrance: !isShuffling)
                    .transition(.opacity)
            }
        }
    }

    /// The song to render in `activeContent`, if any. Returns nil during shuffle so
    /// the pre-playback copy stays on screen from the wheel tap all the way to audio start.
    private var displayedSong: Song? {
        isShuffling ? nil : playbackState.currentSong
    }

    private var emptyVariant: EmptyPlayerContent.Variant {
        hasSongs ? .armed : .libraryEmpty
    }

    /// Invisible spacer that matches the active content's intrinsic height.
    /// Keeps album art and wheel positions stable across all playback states.
    private var activeHeightReference: some View {
        VStack(spacing: 4) {
            Text(" ")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(" ")
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
            // Matches PlaybackProgressBar layout: track + spacing + time labels
            VStack(spacing: 6) {
                Color.clear.frame(height: 12)
                Text(" ")
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            }
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    private func activeContent(song: Song) -> some View {
        VStack(spacing: 4) {
            Text(song.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.3), value: song.title)
                .accessibilityIdentifier("player.songTitle")
            Text(song.artist)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.3), value: song.artist)
                .accessibilityIdentifier("player.songArtist")

            if let progressState {
                LivePlaybackProgressBar(
                    progressState: progressState,
                    onSeek: onSeek
                )
                .padding(.top, 14)
            }
        }
    }

}

// MARK: - Empty Player Content

private struct EmptyPlayerContent: View {
    enum Variant {
        case libraryEmpty
        case armed

        var text: String {
            switch self {
            case .libraryEmpty: return "Start shuffling"
            case .armed: return "Ready to shuffle"
            }
        }
    }

    @Environment(\.shuffleTheme) private var theme

    let variant: Variant
    @State private var appeared: Bool

    init(variant: Variant, animateEntrance: Bool = true) {
        self.variant = variant
        self._appeared = State(wrappedValue: !animateEntrance)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .bold))
                Text(variant.text)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: variant.text)
            }
            .foregroundStyle(theme.textColor)
            .lineLimit(1)
        }
        .offset(y: appeared ? 0 : 12)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.5).delay(0.1), value: appeared)
        .onAppear {
            guard !appeared else { return }
            appeared = true
        }
    }
}
