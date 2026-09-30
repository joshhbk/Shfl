import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    @ObservationIgnored let library: MusicAuthorizing & LibraryCatalog
    @ObservationIgnored let playbackTransport: PlaybackTransport
    @ObservationIgnored let lastFMTransport: LastFMTransport?

    @ObservationIgnored private let sessionHost: ListeningSessionHost
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker

    /// Pre-fetched library songs, ready for instant shuffle on play press
    @ObservationIgnored private var prefetchedSongs: [Song]?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    var showingManage = false
    var showingPicker = false
    var showingPickerDirect = false
    var showingSettings = false

    var isAuthorized = false
    var isShuffling = false
    var isLoading = true
    var loadingMessage = "Loading..."
    var authorizationError: String?

    var player: ShufflePlayer { sessionHost.player }

    init(
        library: MusicAuthorizing & LibraryCatalog,
        playbackTransport: PlaybackTransport,
        modelContext: ModelContext,
        appSettings: AppSettings,
        lifecyclePersistenceHook: (() -> Void)? = nil,
        scrobblingEnabled: Bool = true
    ) {
        self.library = library
        self.playbackTransport = playbackTransport
        self.appSettings = appSettings
        self.sessionHost = ListeningSessionHost(
            playbackTransport: playbackTransport,
            archive: SessionArchive(modelContext: modelContext),
            initialAlgorithm: appSettings.shuffleAlgorithm,
            lifecyclePersistenceHook: lifecyclePersistenceHook
        )

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
        self.scrobbleTracker = ScrobbleTracker(scrobbleManager: scrobbleManager, playbackTransport: playbackTransport)
        scrobbleTracker.start(consuming: player.playbackTransitions)
    }

    func onAppear() async {
        async let authStatus = library.isAuthorized
        await sessionHost.restoreSavedSession()
        isAuthorized = await authStatus
        isLoading = false
    }

    func requestAuthorization() async {
        isAuthorized = await library.requestAuthorization()
        if !isAuthorized {
            authorizationError = "Apple Music access is required to use Shuffled. Please enable it in Settings."
        }
    }

    func autofillLibrary() async {
        isLoading = true
        loadingMessage = "Finding songs in your library..."
        do {
            let source = LibraryAutofillSource(
				libraryCatalog: library,
                algorithm: appSettings.autofillAlgorithm
            )
            let songs = try await source.fetchSongs(excluding: Set(), limit: SessionDraft.maxSongs)
            try player.seedSongs(songs)
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
				libraryCatalog: library,
                    algorithm: appSettings.autofillAlgorithm
                )
                songs = try await source.fetchSongs(excluding: Set(), limit: SessionDraft.maxSongs)
            }
            try player.seedSongs(songs)
            try await player.startFreshShuffle(
                algorithm: appSettings.shuffleAlgorithm
            )
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
                    libraryCatalog: library,
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
    }

    func openPicker() {
        showingPicker = true
    }

    func closePicker() {
        showingPicker = false
    }

    func openPickerDirect() {
        showingPickerDirect = true
    }

    func closePickerDirect() {
        showingPickerDirect = false
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
}
