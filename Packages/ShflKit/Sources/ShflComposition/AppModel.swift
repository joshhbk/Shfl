import Foundation
import Observation
import ShflAppleMusic
import ShflCore
import ShflLastFM
import SwiftData

@Observable
@MainActor
public final class AppModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    public enum LaunchPhase: Equatable {
        case loading
        case needsAuthorization
        case authorizationDenied
        case ready
    }

    public private(set) var launchPhase: LaunchPhase = .loading

    @ObservationIgnored public let sessionHost: ListeningSessionHost
    public var player: ShufflePlayer { sessionHost.player }
    public var sessionDraft: SessionDraftStore { sessionHost.sessionDraft }

    @ObservationIgnored public let libraryPreferences: LibraryPreferences
    @ObservationIgnored public let lastFM: LastFMAccount
    @ObservationIgnored public let artworkStore: ArtworkStore?

    @ObservationIgnored let library: MusicAuthorizing & LibraryCatalog
    @ObservationIgnored let playbackTransport: PlaybackTransport
    /// Held only so the store lives as long as the model.
    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker

    package init(
        library: MusicAuthorizing & LibraryCatalog,
        playbackTransport: PlaybackTransport,
        modelContainer: ModelContainer,
        libraryPreferences: LibraryPreferences,
        savedAlgorithm: SavedShuffleAlgorithm,
        lastFMTransport: LastFMTransport?,
        artworkStore: ArtworkStore?,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.library = library
        self.playbackTransport = playbackTransport
        self.modelContainer = modelContainer
        self.libraryPreferences = libraryPreferences
        self.artworkStore = artworkStore
        self.sessionHost = ListeningSessionHost(
            playbackTransport: playbackTransport,
            archive: SessionArchive(modelContext: modelContainer.mainContext),
            autofillSource: WarmedLibraryAutofillSource(
                libraryCatalog: library,
                algorithm: { [libraryPreferences] in libraryPreferences.autofillAlgorithm }
            ),
            initialAlgorithm: savedAlgorithm.load(),
            saveAlgorithm: { savedAlgorithm.save($0) },
            lifecyclePersistenceHook: lifecyclePersistenceHook
        )

        self.lastFM = LastFMAccount(connection: lastFMTransport)
        let scrobbleManager = ScrobbleManager(transports: lastFMTransport.map { [$0] } ?? [])
        self.scrobbleTracker = ScrobbleTracker(scrobbleManager: scrobbleManager, playbackTransport: playbackTransport)
        scrobbleTracker.start(consuming: player.playbackTransitions)
    }

    public func launch() async {
        async let authStatus = library.isAuthorized
        await sessionHost.restoreSavedSession()
        launchPhase = await authStatus ? .ready : .needsAuthorization
    }

    public func requestAuthorization() async {
        launchPhase = await library.requestAuthorization() ? .ready : .authorizationDenied
    }

    public func sceneDidLeaveForeground() {
        sessionHost.sceneDidLeaveForeground()
    }

    // MARK: - Models for screens

    public func makePlaybackClock() -> PlaybackClock {
        PlaybackClock(playbackTransport: playbackTransport)
    }

    public func makeLibraryBrowser() -> LibraryBrowser {
        LibraryBrowser(libraryCatalog: library, preferences: libraryPreferences)
    }

    public func makeSongs(by artist: Artist) -> ArtistDetailViewModel {
        ArtistDetailViewModel(artistName: artist.name, libraryCatalog: library)
    }

    public func makeSongs(in playlist: Playlist) -> PlaylistDetailViewModel {
        PlaylistDetailViewModel(playlistId: playlist.id, playlistName: playlist.name, libraryCatalog: library)
    }

    public func makeDraftEditor() -> SessionDraftEditor {
        SessionDraftEditor(draft: sessionDraft)
    }
}
