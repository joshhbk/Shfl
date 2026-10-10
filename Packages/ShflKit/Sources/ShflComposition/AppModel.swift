import Foundation
import Observation
import ShflAppleMusic
import ShflCore
import ShflLastFM
import SwiftData

/// Everything a shell needs from one launch. Shells get the observable models
/// from here and never see the catalog, transport or Last.fm adapters behind
/// them.
@Observable
@MainActor
public final class AppModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    /// Where this launch is on the way to a playable library.
    public enum LaunchPhase: Equatable {
        /// Restoring the saved session and checking Apple Music access.
        case loading
        case needsAuthorization
        /// The listener was asked for Apple Music access and declined.
        case authorizationDenied
        case ready
    }

    public private(set) var launchPhase: LaunchPhase = .loading

    @ObservationIgnored public let sessionHost: ListeningSessionHost
    public var player: ShufflePlayer { sessionHost.player }
    public var sessionDraft: SessionDraftStore { sessionHost.sessionDraft }

    @ObservationIgnored public let libraryPreferences: LibraryPreferences
    /// Signed out for good when this launch doesn't talk to Last.fm.
    @ObservationIgnored public let lastFM: LastFMAccount
    /// Nil when this launch has no Apple Music library to draw artwork from,
    /// so artwork views show placeholders.
    @ObservationIgnored public let artworkStore: ArtworkStore?

    @ObservationIgnored let library: MusicAuthorizing & LibraryCatalog
    @ObservationIgnored let playbackTransport: PlaybackTransport
    /// Held so the store lives exactly as long as the model.
    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker

    /// - Parameter lastFMTransport: Nil turns scrobbling off and leaves
    ///   `lastFM` signed out.
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

    /// Restores the saved session and checks Apple Music access. Afterwards
    /// the launch phase is `.ready` or `.needsAuthorization`.
    public func launch() async {
        async let authStatus = library.isAuthorized
        await sessionHost.restoreSavedSession()
        launchPhase = await authStatus ? .ready : .needsAuthorization
    }

    /// Asks for Apple Music access. Afterwards the launch phase is `.ready`
    /// or `.authorizationDenied`.
    public func requestAuthorization() async {
        launchPhase = await library.requestAuthorization() ? .ready : .authorizationDenied
    }

    /// Saves the live playback position on the active session.
    public func sceneDidLeaveForeground() {
        sessionHost.sceneDidLeaveForeground()
    }

    // MARK: - Models for screens

    /// Each call returns a new clock; the screen showing it owns it.
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

    /// An editor for this launch's session draft.
    public func makeDraftEditor() -> SessionDraftEditor {
        SessionDraftEditor(draft: sessionDraft)
    }
}
