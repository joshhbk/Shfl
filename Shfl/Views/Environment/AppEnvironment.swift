import SwiftUI

extension EnvironmentValues {
    /// Library sort order and autofill algorithm. `MainView` provides the
    /// app's preferences.
    @Entry var libraryPreferences: LibraryPreferences? = nil

    /// The current theme. `MainView` provides the app's settings.
    @Entry var appearanceSettings: AppearanceSettings? = nil

    @Entry var shufflePlayer: ShufflePlayer? = nil

    @Entry var lastFMTransport: LastFMTransport? = nil

    /// The session draft that views read and edit. `MainView` provides the
    /// app's store; previews get an empty one.
    @Entry var sessionDraft = SessionDraftStore()

    /// The launch's listening session host. `MainView` provides it; without
    /// it there is nothing to start, so views do nothing rather than drive a
    /// stand-in.
    @Entry var listeningSessionHost: ListeningSessionHost? = nil
}
