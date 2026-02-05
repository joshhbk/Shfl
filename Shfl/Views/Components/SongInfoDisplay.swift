import SwiftUI

/// Displays song title, artist, and optional progress bar based on playback state
struct SongInfoDisplay: View {
    @Environment(\.shuffleTheme) private var theme

    let playbackState: PlaybackState
    let hasSongs: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let showProgressBar: Bool
    let onSeek: (TimeInterval) -> Void
    let onAddSongs: () -> Void

    init(
        playbackState: PlaybackState,
        hasSongs: Bool = false,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        showProgressBar: Bool = FeatureFlags.showProgressBar,
        onSeek: @escaping (TimeInterval) -> Void = { _ in },
        onAddSongs: @escaping () -> Void = {}
    ) {
        self.playbackState = playbackState
        self.hasSongs = hasSongs
        self.currentTime = currentTime
        self.duration = duration
        self.showProgressBar = showProgressBar
        self.onSeek = onSeek
        self.onAddSongs = onAddSongs
    }

    var body: some View {
        PlaybackStateContent(
            playbackState: playbackState,
            loading: { _ in
                // Show skeleton during loading for cleaner transition to playing
                idleContent
            },
            active: { song in
                activeContent(song: song)
            },
            empty: {
                if hasSongs {
                    idleContent
                } else {
                    emptyContent
                }
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
    private var idleContent: some View {
        // Reserve space for song info area (no visible content in idle state)
        // Song name and artist will animate in when playback starts
        Color.clear
            .frame(height: showProgressBar ? 20 + 13 + 14 + 33 : 20 + 13) // title + artist + progress bar space
    }

    @ViewBuilder
    private var emptyContent: some View {
        VStack(spacing: 12) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textColor)

            Button(action: onAddSongs) {
                Label("Add Songs", systemImage: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ctaTextColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(ctaBackgroundColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// CTA button background - contrasts with theme
    private var ctaBackgroundColor: Color {
        switch theme.textStyle {
        case .light:
            // Light text themes (pink, orange, etc.) - use dark background
            return Color.black.opacity(0.7)
        case .dark:
            // Dark text themes (silver) - use dark background too for consistency
            return Color.black.opacity(0.8)
        }
    }

    /// CTA button text - always light on dark background
    private var ctaTextColor: Color {
        .white
    }
}
