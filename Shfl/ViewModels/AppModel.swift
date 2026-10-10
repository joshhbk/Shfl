import Foundation
import ShflCore
import ShflLastFM
import SwiftData

@Observable
@MainActor
final class AppModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    @ObservationIgnored let library: MusicAuthorizing & LibraryCatalog
    @ObservationIgnored let playbackTransport: PlaybackTransport
    @ObservationIgnored let lastFM: LastFMAccount

    @ObservationIgnored let sessionHost: ListeningSessionHost
    @ObservationIgnored private let libraryPreferences: LibraryPreferences
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker

    enum LaunchPhase: Equatable {
        case loading
        case needsAuthorization
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
            self.lastFM = LastFMAccount(connection: lastFMTransport)
            scrobbleTransports = [lastFMTransport]
        } else {
            self.lastFM = LastFMAccount(connection: nil)
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

    func sceneDidLeaveForeground() {
        sessionHost.sceneDidLeaveForeground()
    }

    func requestAuthorization() async {
        launchPhase = await library.requestAuthorization() ? .ready : .authorizationDenied
    }
}
