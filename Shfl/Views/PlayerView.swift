import SwiftUI

struct PlayerView: View {
    var player: ShufflePlayer
    let musicService: MusicService
    let onManageTapped: () -> Void
    let onAddTapped: () -> Void
    let onSettingsTapped: () -> Void

    @Environment(\.motionManager) private var motionManager
    @State private var themeController = ThemeController()
    @State private var tintProvider = TintedThemeProvider()
    @State private var progressState: PlayerProgressState?
    @State private var colorExtractor = AlbumArtColorExtractor()
    @State private var highlightOffset: CGPoint = .zero
    @State private var showError = false
    @State private var errorMessage = ""

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        onManageTapped: @escaping () -> Void,
        onAddTapped: @escaping () -> Void = {},
        onSettingsTapped: @escaping () -> Void = {}
    ) {
        self.player = player
        self.musicService = musicService
        self.onManageTapped = onManageTapped
        self.onAddTapped = onAddTapped
        self.onSettingsTapped = onSettingsTapped
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BrushedMetalBackground(highlightOffset: highlightOffset)

                ClassicPlayerLayout(
                    playbackState: player.playbackState,
                    isControlsDisabled: player.songCount == 0,
                    currentTime: progressState?.currentTime ?? 0,
                    duration: progressState?.duration ?? 0,
                    highlightOffset: highlightOffset,
                    actions: actions,
                    showError: showError,
                    errorMessage: errorMessage,
                    safeAreaInsets: geometry.safeAreaInsets,
                    onDismissError: {
                        withAnimation {
                            showError = false
                        }
                    }
                )
            }
            .ignoresSafeArea()
        }
        .simultaneousGesture(themeController.makeSwipeGesture())
        .environment(\.shuffleTheme, tintProvider.computedTheme)
        .onAppear {
            if progressState == nil {
                progressState = PlayerProgressState(musicService: musicService)
            }
            progressState?.startUpdating()
            motionManager?.start(
                sensitivity: themeController.currentTheme.motionSensitivity,
                maxOffset: 220
            )

            // Initialize tint provider with current theme
            tintProvider.update(albumColor: colorExtractor.extractedColor, theme: themeController.currentTheme)

            if let song = player.playbackState.currentSong {
                colorExtractor.updateColor(for: song.id)
            }
        }
        .onDisappear {
            progressState?.stopUpdating()
            motionManager?.stop()
        }
        .onChange(of: player.playbackState) { _, newState in
            handlePlaybackStateChange(newState)
        }
        .onChange(of: motionManager?.highlightOffset) { _, newOffset in
            highlightOffset = newOffset ?? .zero
        }
        .onChange(of: colorExtractor.extractedColor) { _, newColor in
            tintProvider.update(albumColor: newColor, theme: themeController.currentTheme)
        }
        .onChange(of: themeController.currentTheme) { _, newTheme in
            tintProvider.update(albumColor: colorExtractor.extractedColor, theme: newTheme)
            motionManager?.updateSettings(
                sensitivity: newTheme.motionSensitivity,
                maxOffset: 220
            )
        }
    }

    // MARK: - Actions

    private var actions: PlayerActions {
        PlayerActions(
            onPlayPause: handlePlayPause,
            onSkipForward: handleSkipForward,
            onSkipBack: handleSkipBack,
            onManage: onManageTapped,
            onAdd: onAddTapped,
            onSettings: onSettingsTapped,
            onSeek: handleSeek
        )
    }

    private func handleSeek(_ time: TimeInterval) {
        musicService.seek(to: time)
    }

    private func handlePlayPause() {
        Task {
            try? await player.togglePlayback()
        }
    }

    private func handleSkipForward() {
        Task {
            try? await player.skipToNext()
        }
    }

    private func handleSkipBack() {
        Task {
            try? await player.restartOrSkipToPrevious()
        }
    }

    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        if case .error(let error) = newState {
            errorMessage = error.localizedDescription
            withAnimation {
                showError = true
            }
        }

        // Reset progress immediately so the bar doesn't show stale time
        progressState?.resetToCurrentPosition()

        if let song = newState.currentSong {
            colorExtractor.updateColor(for: song.id)
        } else {
            colorExtractor.clear()
        }
    }

}

// MARK: - Previews

private final class PreviewMockMusicService: MusicService, @unchecked Sendable {
    let initialState: PlaybackState

    init(initialState: PlaybackState = .empty) {
        self.initialState = initialState
    }

    var isAuthorized: Bool { true }
    var currentPlaybackTime: TimeInterval { 78 }
    var currentSongDuration: TimeInterval { 242 }
    var playbackStateStream: AsyncStream<PlaybackState> {
        let state = initialState
        return AsyncStream { continuation in
            continuation.yield(state)
        }
    }
    func requestAuthorization() async -> Bool { true }
    func prefetchLibrary() async {}
    func fetchLibrarySongs(sortedBy: SortOption, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }
    func searchLibrarySongs(query: String) async throws -> [Song] { [] }
    func setQueue(songs: [Song]) async throws {}
    func insertIntoQueue(songs: [Song]) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
    func skipToPrevious() async throws {}
    func restartOrSkipToPrevious() async throws {}
    func seek(to time: TimeInterval) {}
}

private let previewSong = Song(
    id: "preview-1",
    title: "Bohemian Rhapsody",
    artist: "Queen",
    albumTitle: "A Night at the Opera",
    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/3c/1b/a9/3c1ba9e1-cf27-f6d1-6287-a3f0be3483a0/00602547288233.rgb.jpg/600x600bb.jpg")
)

#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {},
        onSettingsTapped: {}
    )
}

#Preview("Playing") {
    ZStack {
        GeometryReader { geometry in
            Image("SampleAlbumArt")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .blur(radius: 3)
                .ignoresSafeArea()
        }

        VStack(spacing: 0) {
            HStack {
                Button(action: {}) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(ShuffleTheme.silver.bodyGradientTop)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        )
                }
                Spacer()
                Button(action: {}) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(ShuffleTheme.silver.bodyGradientTop)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            ShuffleBodyView(highlightOffset: .zero, height: 120) {
                VStack(spacing: 4) {
                    Text(previewSong.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ShuffleTheme.silver.textColor)
                        .lineLimit(1)
                    Text(previewSong.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(ShuffleTheme.silver.secondaryTextColor)
                        .lineLimit(1)

                    PlaybackProgressBar(currentTime: 78, duration: 242)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ShuffleBodyView(highlightOffset: .zero) {
                ClickWheelView(
                    isPlaying: true,
                    onPlayPause: {},
                    onSkipForward: {},
                    onSkipBack: {},
                    onVolumeUp: {},
                    onVolumeDown: {},
                    highlightOffset: .zero,
                    scale: 0.6
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
    }
    .environment(\.shuffleTheme, .silver)
}
