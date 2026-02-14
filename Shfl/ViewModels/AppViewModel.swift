import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    let player: ShufflePlayer
    let playbackCoordinator: PlaybackCoordinator
    @ObservationIgnored let musicService: MusicService
    @ObservationIgnored let lastFMTransport: LastFMTransport

    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let sessionCoordinator: AppPlaybackSessionCoordinator

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
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.musicService = musicService
        let player = ShufflePlayer(musicService: musicService)
        self.player = player
        self.playbackCoordinator = PlaybackCoordinator(player: player, appSettings: appSettings)
        self.appSettings = appSettings

        // Setup scrobbling
        self.lastFMTransport = LastFMTransport(
            apiKey: LastFMConfig.apiKey,
            sharedSecret: LastFMConfig.sharedSecret
        )
        let scrobbleManager = ScrobbleManager(transports: [lastFMTransport])
        let scrobbleTracker = ScrobbleTracker(scrobbleManager: scrobbleManager, musicService: musicService)

        self.sessionCoordinator = AppPlaybackSessionCoordinator(
            player: player,
            playbackCoordinator: playbackCoordinator,
            musicService: musicService,
            repository: SongRepository(modelContext: modelContext),
            playbackStateRepository: PlaybackStateRepository(modelContext: modelContext),
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

    func shuffleAll() async {
        isShuffling = true
        do {
            let source = LibraryAutofillSource(
                musicService: musicService,
                algorithm: appSettings.autofillAlgorithm
            )
            let songs = try await source.fetchSongs(excluding: Set(), limit: QueueState.maxSongs)
            try await playbackCoordinator.seedSongs(songs)
            try await playbackCoordinator.play()
            sessionCoordinator.persistSongs()
        } catch {
            print("Failed to shuffle all: \(error)")
        }
        // Clear after play() returns — view guards isShuffling in both
        // the empty and loading slots to keep the spinner visible until .playing
        isShuffling = false
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
        await playbackCoordinator.reshuffleAlgorithm(algorithm)
    }

    func togglePlayback() async {
        try? await playbackCoordinator.togglePlayback()
    }

    func skipToNext() async {
        try? await playbackCoordinator.skipToNext()
    }

    func restartOrSkipToPrevious() async {
        try? await playbackCoordinator.restartOrSkipToPrevious()
    }

    func addSong(_ song: Song) async throws {
        try await playbackCoordinator.addSong(song)
    }

    func addSongsWithQueueRebuild(_ songs: [Song]) async throws {
        try await playbackCoordinator.addSongsWithQueueRebuild(songs)
    }

    func removeSong(id: String) async {
        await playbackCoordinator.removeSong(id: id)
    }

    func removeAllSongs() async {
        await playbackCoordinator.removeAllSongs()
    }

    func persistPlaybackState() {
        sessionCoordinator.persistPlaybackState()
    }
}
