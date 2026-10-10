import ShflCore
import SwiftUI

extension EnvironmentValues {
    @Entry var libraryPreferences: LibraryPreferences? = nil

    @Entry var appearanceSettings: AppearanceSettings? = nil

    @Entry var shufflePlayer: ShufflePlayer? = nil

    @Entry var listeningSessionHost: ListeningSessionHost? = nil
}
