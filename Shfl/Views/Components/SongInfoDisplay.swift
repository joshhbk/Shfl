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

            PlaybackStateContent(
                playbackState: playbackState,
                loading: { _ in
                    if isShuffling {
                        EmptyPlayerContent(animateEntrance: false)
                    }
                },
                active: { song in
                    activeContent(song: song)
                },
                empty: {
                    if !hasSongs || isShuffling {
                        EmptyPlayerContent(animateEntrance: !isShuffling)
                    }
                }
            )
        }
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
            Text(song.artist)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.3), value: song.artist)

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
    @Environment(\.shuffleTheme) private var theme

    @State private var appeared: Bool

    init(animateEntrance: Bool = true) {
        self._appeared = State(wrappedValue: !animateEntrance)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .bold))
                Text("Ready to shuffle")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
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
