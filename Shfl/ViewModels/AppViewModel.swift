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
    var sessionDraft: SessionDraftStore { sessionHost.sessionDraft }

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
            try await sessionDraft.autofill(from: source)
        } catch {
            print("Failed to autofill library: \(error)")
        }
        isLoading = false
    }

    func shuffleAll() async {
        isShuffling = true
        do {
            if let prefetched = prefetchedSongs {
                prefetchedSongs = nil
                prefetchTask = nil
                try sessionDraft.add(prefetched)
            } else {
                prefetchTask?.cancel()
                prefetchTask = nil
                let source = LibraryAutofillSource(
                    libraryCatalog: library,
                    algorithm: appSettings.autofillAlgorithm
                )
                try await sessionDraft.autofill(from: source)
            }
            try await player.startFreshShuffle()
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
              sessionDraft.isEmpty,
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

    // MARK: - Playback Commands

    func togglePlayback() async {
        try? await player.togglePlayback()
    }

    func skipToNext() async {
        try? await player.skipToNext()
    }

    func restartOrSkipToPrevious() async {
        try? await player.restartOrSkipToPrevious()
    }
}
