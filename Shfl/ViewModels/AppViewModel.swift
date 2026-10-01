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

    var showingManage = false
    var showingPicker = false
    var showingPickerDirect = false
    var showingSettings = false

    var isAuthorized = false
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
            makeAutofillSource: { [library, appSettings] in
                LibraryAutofillSource(
                    libraryCatalog: library,
                    algorithm: appSettings.autofillAlgorithm
                )
            },
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
}
