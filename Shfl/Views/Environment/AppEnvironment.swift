import ShflCore
import SwiftUI

extension EnvironmentValues {
    @Entry var libraryPreferences: LibraryPreferences? = nil

    @Entry var appearanceSettings: AppearanceSettings? = nil

    /// Provided by `MainView`; nil outside it, such as in previews.
    @Entry var shufflePlayer: ShufflePlayer? = nil

    /// The launch's listening session host, provided by `MainView`. When it
    /// is nil, such as in previews, controls that start playback do nothing.
    @Entry var listeningSessionHost: ListeningSessionHost? = nil
}
