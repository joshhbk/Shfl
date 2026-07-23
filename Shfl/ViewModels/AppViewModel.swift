import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    let player: ShufflePlayer
    @ObservationIgnored let musicService: MusicService
    @ObservationIgnored let lastFMTransport: LastFMTransport?

    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let sessionCoordinator: AppPlaybackSessionCoordinator

    /// Pre-fetched library songs, ready for instant shuffle on play press
    @ObservationIgnored private var prefetchedSongs: [Song]?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    var showingManage = false
    var showingPicker = false
    var showingPickerDirect = false
    var showingSettings = false

    var isAuthorized: Bool {
        get { sessionCoordinator.isAuthorized }
        set { sessionCoordinator.isAuthorized = newValue }
    }

    var isShuffling = false

    var isLoading: Bool {
        get { sessionCoordinator.isLoading }
        set { sessionCoordinator.isLoading = newValue }
    }

    var loadingMessage: String {
        get { sessionCoordinator.loadingMessage }
        set { sessionCoordinator.loadingMessage = newValue }
    }

    var authorizationError: String? {
        get { sessionCoordinator.authorizationError }
        set { sessionCoordinator.authorizationError = newValue }
    }

    /// Whether playback state was restored from persistence
    var didRestorePlaybackState: Bool {
        sessionCoordinator.didRestorePlaybackState
    }

    init(
        musicService: MusicService,
        modelContext: ModelContext,
        appSettings: AppSettings,
        lifecyclePersistenceHook: (() -> Void)? = nil,
        scrobblingEnabled: Bool = true
    ) {
        self.musicService = musicService
        let player = ShufflePlayer(
            playbackTransport: musicService,
            initialAlgorithm: appSettings.shuffleAlgorithm
        )
        self.player = player
        self.appSettings = appSettings

        let scrobbleTransports: [any ScrobbleTransport]
        if scrobblingEnabled {
            let lastFMTransport = LastFMTransport(
                apiKey: LastFMConfig.apiKey,
                sharedSecret: LastFMConfig.sharedSecret
            )
            self.lastFMTransport = lastFMTransport
            scrobbleTransports = [lastFMTransport]
        } else {
            self.lastFMTransport = nil
            scrobbleTransports = []
        }
        let scrobbleManager = ScrobbleManager(transports: scrobbleTransports)
        let scrobbleTracker = ScrobbleTracker(scrobbleManager: scrobbleManager, playbackTransport: musicService)
        let songRepository = SongRepository(modelContext: modelContext)
        let playbackStateRepository = PlaybackStateRepository(modelContext: modelContext)
        let sessionSnapshotService = SessionSnapshotService(
            songRepository: songRepository,
            playbackStateRepository: playbackStateRepository
        )

        self.sessionCoordinator = AppPlaybackSessionCoordinator(
            player: player,
            authorizer: musicService,
            playbackTransport: musicService,
            sessionSnapshotService: sessionSnapshotService,
            scrobbleTracker: scrobbleTracker,
            lifecyclePersistenceHook: lifecyclePersistenceHook
        )
    }

    func onAppear() async {
        await sessionCoordinator.onAppear()
    }

    func requestAuthorization() async {
        await sessionCoordinator.requestAuthorization()
    }

    func handleDidEnterBackground() {
        sessionCoordinator.handleDidEnterBackground()
    }

    func persistSongs() {
        sessionCoordinator.persistSongs()
    }

    func autofillLibrary() async {
        isLoading = true
        loadingMessage = "Finding songs in your library..."
        do {
            let source = LibraryAutofillSource(
				libraryCatalog: musicService,
                algorithm: appSettings.autofillAlgorithm
            )
            let songs = try await source.fetchSongs(excluding: Set(), limit: SessionDraft.maxSongs)
            try player.seedSongs(songs)
            sessionCoordinator.persistSongs()
        } catch {
            print("Failed to autofill library: \(error)")
        }
        isLoading = false
    }

    func shuffleAll() async {
        isShuffling = true
        do {
            let songs: [Song]
            if let prefetched = prefetchedSongs {
                songs = prefetched
                prefetchedSongs = nil
                prefetchTask = nil
            } else {
                prefetchTask?.cancel()
                prefetchTask = nil
                let source = LibraryAutofillSource(
				libraryCatalog: musicService,
                    algorithm: appSettings.autofillAlgorithm
                )
                songs = try await source.fetchSongs(excluding: Set(), limit: SessionDraft.maxSongs)
            }
            try player.seedSongs(songs)
            try await player.startFreshShuffle(
                algorithm: appSettings.shuffleAlgorithm
            )
            sessionCoordinator.persistSongs()
        } catch {
            print("Failed to shuffle all: \(error)")
        }
        // Clear after play() returns — view guards isShuffling in both
        // the empty and loading slots to keep the spinner visible until .playing
        isShuffling = false
    }

    /// Starts a background library fetch so songs are ready when the user presses play.
    /// Safe to call multiple times — guards against redundant work.
    func prefetchLibraryIfNeeded() {
        guard isAuthorized,
              player.draftIsEmpty,
              prefetchedSongs == nil,
              prefetchTask == nil else { return }

        prefetchTask = Task {
            do {
                let source = LibraryAutofillSource(
                    libraryCatalog: musicService,
                    algorithm: appSettings.autofillAlgorithm
                )
                let songs = try await source.fetchSongs(excluding: Set(), limit: SessionDraft.maxSongs)
                guard !Task.isCancelled else { return }
                self.prefetchedSongs = songs
            } catch {
                // Silent — shuffleAll fetches fresh on miss
            }
            self.prefetchTask = nil
        }
    }

    func openManage() {
        showingManage = true
    }

    func closeManage() {
        showingManage = false
        sessionCoordinator.persistSongs()
    }

    func openPicker() {
        showingPicker = true
    }

    func closePicker() {
        showingPicker = false
        sessionCoordinator.persistSongs()
    }

    func openPickerDirect() {
        showingPickerDirect = true
    }

    func closePickerDirect() {
        showingPickerDirect = false
        sessionCoordinator.persistSongs()
    }

    func openSettings() {
        showingSettings = true
    }

    func closeSettings() {
        showingSettings = false
    }

    // MARK: - Coordinator Commands

    func onShuffleAlgorithmChanged(_ algorithm: ShuffleAlgorithm) async {
        player.stageAlgorithm(algorithm)
    }

    func togglePlayback() async {
        try? await player.togglePlayback(algorithm: appSettings.shuffleAlgorithm)
    }

    func skipToNext() async {
        try? await player.skipToNext()
    }

    func restartOrSkipToPrevious() async {
        try? await player.restartOrSkipToPrevious()
    }

    func addSong(_ song: Song) async throws {
        try await player.addSong(song)
    }

    func addSongsWithQueueRebuild(_ songs: [Song]) async throws {
        try await player.addSongsWithQueueRebuild(
            songs,
            algorithm: appSettings.shuffleAlgorithm
        )
    }

    func removeSong(id: String) async {
        await player.removeSong(id: id)
    }

    func removeAllSongs() async {
        await player.removeAllSongs()
    }

    func persistPlaybackState() {
        sessionCoordinator.persistPlaybackState()
    }
}
