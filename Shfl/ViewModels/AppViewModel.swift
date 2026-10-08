import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    @ObservationIgnored let library: MusicAuthorizing & LibraryCatalog
    @ObservationIgnored let playbackTransport: PlaybackTransport
    @ObservationIgnored let lastFMTransport: LastFMTransport?

    @ObservationIgnored let sessionHost: ListeningSessionHost
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker

    var showingPicker = false
    var showingSettings = false

    var isAuthorized = false
    var isLoading = true
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
            autofillSource: WarmedLibraryAutofillSource(
                libraryCatalog: library,
                algorithm: { [appSettings] in appSettings.autofillAlgorithm }
            ),
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

    func openPicker() {
        showingPicker = true
    }

    func closePicker() {
        showingPicker = false
    }

    func openSettings() {
        showingSettings = true
    }

    func closeSettings() {
        showingSettings = false
    }
}
