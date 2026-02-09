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
    let onShuffle: () -> Void
    let isShuffling: Bool
    let onPlayPause: () -> Void

    init(
        playbackState: PlaybackState,
        hasSongs: Bool = false,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        showProgressBar: Bool = FeatureFlags.showProgressBar,
        onSeek: @escaping (TimeInterval) -> Void = { _ in },
        onAddSongs: @escaping () -> Void = {},
        onShuffle: @escaping () -> Void = {},
        isShuffling: Bool = false,
        onPlayPause: @escaping () -> Void = {}
    ) {
        self.playbackState = playbackState
        self.hasSongs = hasSongs
        self.currentTime = currentTime
        self.duration = duration
        self.showProgressBar = showProgressBar
        self.onSeek = onSeek
        self.onAddSongs = onAddSongs
        self.onShuffle = onShuffle
        self.isShuffling = isShuffling
        self.onPlayPause = onPlayPause
    }

    var body: some View {
        PlaybackStateContent(
            playbackState: playbackState,
            loading: { _ in
                if isShuffling {
                    emptyContent
                } else {
                    idleContent
                }
            },
            active: { song in
                activeContent(song: song)
            },
            empty: {
                if hasSongs && !isShuffling {
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
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
            Text(song.artist)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func activeContent(song: Song) -> some View {
        VStack(spacing: 4) {
            Text(song.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
            Text(song.artist)
                .font(.system(size: 15, weight: .medium))
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

    private var idleContentHeight: CGFloat {
        showProgressBar ? 80 : 33
    }

    @ViewBuilder
    private var idleContent: some View {
        Button(action: onPlayPause) {
            Label("Play", systemImage: "play.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ctaTextColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(ctaBackgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(height: idleContentHeight)
    }

    @ViewBuilder
    private var emptyContent: some View {
        VStack(spacing: 12) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textColor)

            HStack(spacing: 12) {
                shuffleButton
                addSongsButton
            }
        }
    }

    private var shuffleButton: some View {
        Button(action: onShuffle) {
            shuffleButtonLabel
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ctaBackgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isShuffling)
    }

    @ViewBuilder
    private var shuffleButtonLabel: some View {
        if isShuffling {
            ProgressView()
                .tint(ctaTextColor)
        } else {
            Label("Shuffle", systemImage: "shuffle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ctaTextColor)
        }
    }

    private var addSongsButton: some View {
        Button(action: onAddSongs) {
            Label("Add Songs", systemImage: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ctaTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ctaBackgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isShuffling)
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
