import Foundation
import SwiftData

@Observable
@MainActor
final class AppModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    @ObservationIgnored let library: MusicAuthorizing & LibraryCatalog
    @ObservationIgnored let playbackTransport: PlaybackTransport
    @ObservationIgnored let lastFMTransport: LastFMTransport?

    @ObservationIgnored let sessionHost: ListeningSessionHost
    @ObservationIgnored private let libraryPreferences: LibraryPreferences
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker

    /// Where this launch is on the way to a playable library.
    enum LaunchPhase: Equatable {
        /// Restoring the saved session and checking Apple Music access.
        case loading
        /// Apple Music access hasn't been granted yet.
        case needsAuthorization
        /// The listener was asked for Apple Music access and declined.
        case authorizationDenied
        case ready
    }

    private(set) var launchPhase: LaunchPhase = .loading

    var player: ShufflePlayer { sessionHost.player }
    var sessionDraft: SessionDraftStore { sessionHost.sessionDraft }

    init(
        library: MusicAuthorizing & LibraryCatalog,
        playbackTransport: PlaybackTransport,
        modelContext: ModelContext,
        libraryPreferences: LibraryPreferences,
        savedAlgorithm: SavedShuffleAlgorithm,
        lifecyclePersistenceHook: (() -> Void)? = nil,
        scrobblingEnabled: Bool = true
    ) {
        self.library = library
        self.playbackTransport = playbackTransport
        self.libraryPreferences = libraryPreferences
        self.sessionHost = ListeningSessionHost(
            playbackTransport: playbackTransport,
            archive: SessionArchive(modelContext: modelContext),
            autofillSource: WarmedLibraryAutofillSource(
                libraryCatalog: library,
                algorithm: { [libraryPreferences] in libraryPreferences.autofillAlgorithm }
            ),
            initialAlgorithm: savedAlgorithm.load(),
            saveAlgorithm: { savedAlgorithm.save($0) },
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
        launchPhase = await authStatus ? .ready : .needsAuthorization
    }

    /// A lifecycle checkpoint for when the shell's scene goes to the
    /// background: the session host saves the live playback position.
    func sceneDidLeaveForeground() {
        sessionHost.sceneDidLeaveForeground()
    }

    /// Asks for Apple Music access. Afterwards the launch phase is `.ready`
    /// or `.authorizationDenied`.
    func requestAuthorization() async {
        launchPhase = await library.requestAuthorization() ? .ready : .authorizationDenied
    }
}
