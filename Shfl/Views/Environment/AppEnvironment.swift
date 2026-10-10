import ShflCore
import SwiftUI

extension EnvironmentValues {
    @Entry var libraryPreferences: LibraryPreferences? = nil

    @Entry var appearanceSettings: AppearanceSettings? = nil

    @Entry var shufflePlayer: ShufflePlayer? = nil

    /// The session draft that views read and edit. `MainView` provides the
    /// app's store; previews get an empty one.
    @Entry var sessionDraft = SessionDraftStore()

    @Entry var listeningSessionHost: ListeningSessionHost? = nil
}
