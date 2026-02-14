import SwiftUI

/// Displays song title, artist, and optional progress bar based on playback state
struct SongInfoDisplay: View {
    @Environment(\.shuffleTheme) private var theme

    let playbackState: PlaybackState
    let hasSongs: Bool
    let progressState: PlayerProgressState?
    let onSeek: (TimeInterval) -> Void
    let onAddSongs: () -> Void
    let onShuffle: () -> Void
    let isShuffling: Bool

    init(
        playbackState: PlaybackState,
        hasSongs: Bool = false,
        progressState: PlayerProgressState? = nil,
        onSeek: @escaping (TimeInterval) -> Void = { _ in },
        onAddSongs: @escaping () -> Void = {},
        onShuffle: @escaping () -> Void = {},
        isShuffling: Bool = false
    ) {
        self.playbackState = playbackState
        self.hasSongs = hasSongs
        self.progressState = progressState
        self.onSeek = onSeek
        self.onAddSongs = onAddSongs
        self.onShuffle = onShuffle
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
                        emptyContent
                    }
                },
                active: { song in
                    activeContent(song: song)
                },
                empty: {
                    if !hasSongs || isShuffling {
                        emptyContent
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
