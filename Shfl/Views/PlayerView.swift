import SwiftUI

struct PlayerView: View {
    var player: ShufflePlayer
    let musicService: MusicService
    let onManageTapped: () -> Void
    let onAddTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onPlayPauseTapped: () -> Void
    let onSkipForwardTapped: () -> Void
    let onSkipBackTapped: () -> Void
    let onShuffle: () -> Void
    let isShuffling: Bool

    @Environment(\.appSettings) private var appSettings
    @State private var themeController: ThemeController
    @State private var tintProvider: TintedThemeProvider
    @State private var progressState: PlayerProgressState?
    @State private var colorExtractor = AlbumArtColorExtractor()
    @State private var showError = false
    @State private var errorMessage = ""

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        initialThemeId: String? = nil,
        onManageTapped: @escaping () -> Void,
        onAddTapped: @escaping () -> Void = {},
        onSettingsTapped: @escaping () -> Void = {},
        onPlayPauseTapped: @escaping () -> Void = {},
        onSkipForwardTapped: @escaping () -> Void = {},
        onSkipBackTapped: @escaping () -> Void = {},
        onShuffle: @escaping () -> Void = {},
        isShuffling: Bool = false
    ) {
        self.player = player
        self.musicService = musicService
        self.onManageTapped = onManageTapped
        self.onAddTapped = onAddTapped
        self.onSettingsTapped = onSettingsTapped
        self.onPlayPauseTapped = onPlayPauseTapped
        self.onSkipForwardTapped = onSkipForwardTapped
        self.onSkipBackTapped = onSkipBackTapped
        self.onShuffle = onShuffle
        self.isShuffling = isShuffling
        self._themeController = State(wrappedValue: ThemeController(themeId: initialThemeId))
        let initialTheme = initialThemeId.flatMap { ShuffleTheme.theme(byId: $0) } ?? .pink
        self._tintProvider = State(wrappedValue: TintedThemeProvider(theme: initialTheme))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BrushedMetalBackground()

                ClassicPlayerLayout(
                    playbackState: player.playbackState,
                    hasSongs: player.songCount > 0,
                    isControlsDisabled: player.songCount == 0,
                    progressState: progressState,
                    onPlayPause: onPlayPauseTapped,
                    onSkipForward: onSkipForwardTapped,
                    onSkipBack: onSkipBackTapped,
                    onAdd: onAddTapped,
                    onSettings: onSettingsTapped,
                    onSeek: { time in
                        progressState?.handleUserSeek(to: time)
                        musicService.seek(to: time)
                    },
                    onShuffle: onShuffle,
                    isShuffling: isShuffling,
                    showError: showError,
                    errorMessage: errorMessage,
                    safeAreaInsets: geometry.safeAreaInsets,
                    onDismissError: {
                        withAnimation {
                            showError = false
                        }
                        player.clearOperationNotice()
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
            progressState?.startUpdating(playbackState: player.playbackState)

            // Initialize tint provider with current theme
            tintProvider.update(albumColor: colorExtractor.extractedColor, theme: themeController.currentTheme)

            if let song = player.playbackState.currentSong {
                colorExtractor.updateColor(for: song.id)
            }
        }
        .onDisappear {
            progressState?.stopUpdating()
        }
        .onChange(of: player.playbackState) { _, newState in
            handlePlaybackStateChange(newState)
        }
        .onChange(of: player.operationNotice) { _, notice in
            guard let notice else { return }
            errorMessage = notice
            withAnimation {
                showError = true
            }
        }
        .onChange(of: colorExtractor.extractedColor) { _, newColor in
            tintProvider.update(albumColor: newColor, theme: themeController.currentTheme)
        }
        // Bi-directional theme sync: ThemeController ↔ AppSettings
        // Loop prevention relies on ThemeController.setTheme(byId:) and AppSettings.currentThemeId
        // both guarding against no-op writes, breaking the onChange cycle.
        .onChange(of: themeController.currentTheme) { _, newTheme in
            tintProvider.update(albumColor: colorExtractor.extractedColor, theme: newTheme)
            appSettings?.currentThemeId = newTheme.id
        }
        .onChange(of: appSettings?.currentThemeId) { _, newId in
            guard let id = newId else { return }
            themeController.setTheme(byId: id)
        }
    }

    // MARK: - State Handlers

    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        if case .error(let error) = newState {
            errorMessage = error.localizedDescription
            withAnimation {
                showError = true
            }
        }

        progressState?.handlePlaybackStateChange(newState)

        if let song = newState.currentSong {
            colorExtractor.updateColor(for: song.id)
        } else {
            colorExtractor.clear()
        }
    }

}

// MARK: - Previews

private enum PreviewPlayerState: String, CaseIterable, Identifiable {
    case empty
    case loading
    case playing
    case paused
    case error

    var id: String { rawValue }
}

private struct PreviewPlaybackError: LocalizedError {
    let errorDescription: String?
}

private final class PreviewMockMusicService: MusicService {
    private var continuations: [AsyncStream<PlaybackState>.Continuation] = []
    private var currentState: PlaybackState = .empty

    var isAuthorized: Bool { true }
    var currentPlaybackTime: TimeInterval { 78 }
    var currentSongDuration: TimeInterval { 242 }
    var currentSongId: String? { currentState.currentSongId }
    var transportQueueEntryCount: Int { currentState.currentSong == nil ? 0 : 1 }
    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuations.append(continuation)
            continuation.yield(currentState)
        }
    }
    func requestAuthorization() async -> Bool { true }
    func fetchLibrarySongs(sortedBy: SortOption, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }
    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }
    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        ArtistPage(artists: [], hasMore: false)
    }
    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        PlaylistPage(playlists: [], hasMore: false)
    }
    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        ArtistPage(artists: [], hasMore: false)
    }
    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        PlaylistPage(playlists: [], hasMore: false)
    }
    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }
    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }
    func setQueue(songs: [Song]) async throws {}
    func replaceQueue(queue: [Song], startAtSongId: String?, policy: QueueApplyPolicy) async throws {}
    func play() async throws {}
    func pause() async {}
    func pauseImmediately() {}
    func skipToNext() async throws {}
    func skipToPrevious() async throws {}
    func restartOrSkipToPrevious() async throws {}
    func seek(to time: TimeInterval) {}

    func emit(_ state: PlaybackState) {
        currentState = state
        continuations.forEach { $0.yield(state) }
    }
}

private let previewSong = Song(
    id: "preview-1",
    title: "Bohemian Rhapsody",
    artist: "Queen",
    albumTitle: "A Night at the Opera",
    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/3c/1b/a9/3c1ba9e1-cf27-f6d1-6287-a3f0be3483a0/00602547288233.rgb.jpg/600x600bb.jpg")
)

private let previewQueueSongs = [
    previewSong,
    Song(
        id: "preview-2",
        title: "Dreams",
        artist: "Fleetwood Mac",
        albumTitle: "Rumours",
        artworkURL: nil
    )
]

private struct PlayerViewPreviewHost: View {
    private let musicService: PreviewMockMusicService
    private let player: ShufflePlayer
    private let themeId: String

    init(state: PreviewPlayerState, themeId: String) {
        self.themeId = themeId

        let musicService = PreviewMockMusicService()
        let player = ShufflePlayer(musicService: musicService)
        try? player.seedSongs(previewQueueSongs)

        switch state {
        case .empty:
            break
        case .loading:
            musicService.emit(.loading(previewSong))
        case .playing:
            musicService.emit(.playing(previewSong))
        case .paused:
            musicService.emit(.paused(previewSong))
        case .error:
            musicService.emit(.error(PreviewPlaybackError(errorDescription: "Preview playback failed.")))
        }

        self.musicService = musicService
        self.player = player
    }

    var body: some View {
        PlayerView(
            player: player,
            musicService: musicService,
            initialThemeId: themeId,
            onManageTapped: {},
            onAddTapped: {},
            onSettingsTapped: {},
            onPlayPauseTapped: {},
            onSkipForwardTapped: {},
            onSkipBackTapped: {},
            onShuffle: {},
            isShuffling: false
        )
    }
}

#Preview("Empty State") {
    PlayerViewPreviewHost(state: .empty, themeId: "silver")
}

#Preview("Loading") {
    PlayerViewPreviewHost(state: .loading, themeId: "silver")
}

#Preview("Playing") {
    PlayerViewPreviewHost(state: .playing, themeId: "silver")
}

#Preview("Paused") {
    PlayerViewPreviewHost(state: .paused, themeId: "silver")
}

#Preview("Error") {
    PlayerViewPreviewHost(state: .error, themeId: "silver")
}
