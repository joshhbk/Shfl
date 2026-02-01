import SwiftUI

/// Displays song title, artist, and optional progress bar based on playback state
struct SongInfoDisplay: View {
    @Environment(\.shuffleTheme) private var theme

    let playbackState: PlaybackState
    let currentTime: TimeInterval
    let duration: TimeInterval
    let showProgressBar: Bool
    let onSeek: (TimeInterval) -> Void

    init(
        playbackState: PlaybackState,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        showProgressBar: Bool = FeatureFlags.showProgressBar,
        onSeek: @escaping (TimeInterval) -> Void = { _ in }
    ) {
        self.playbackState = playbackState
        self.currentTime = currentTime
        self.duration = duration
        self.showProgressBar = showProgressBar
        self.onSeek = onSeek
    }

    var body: some View {
        PlaybackStateContent(
            playbackState: playbackState,
            loading: { song in
                loadingContent(song: song)
            },
            active: { song in
                activeContent(song: song)
            },
            empty: {
                emptyContent
            }
        )
    }

    @ViewBuilder
    private func loadingContent(song: Song) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(theme.textColor)
            Text(song.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
            Text(song.artist)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func activeContent(song: Song) -> some View {
        VStack(spacing: 2) {
            Text(song.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
            Text(song.artist)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)

            if showProgressBar {
                PlaybackProgressBar(
                    currentTime: currentTime,
                    duration: duration,
                    onSeek: onSeek
                )
                .padding(.top, 14)
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        VStack(spacing: 8) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textColor)
            Text("Add some music to get started")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryTextColor)
        }
    }
}
