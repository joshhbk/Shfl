import SwiftUI

extension EnvironmentValues {
    /// Provided by `MainView`; nil outside it, such as in previews.
    @Entry var libraryPreferences: LibraryPreferences? = nil

    /// Provided by `MainView`; nil outside it, such as in previews.
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
