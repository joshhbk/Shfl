import Foundation
import ShflCore
import ShflDeterministic

extension AppModel {
    /// Its settings suite is emptied on each call, so previews never leak into the app's settings.
    public static func preview(
        library: DeterministicLibrary = .sample,
        playback: DeterministicPlayback = DeterministicPlayback(),
        draft: [Song] = []
    ) -> AppModel {
        let defaults = UserDefaults(suiteName: previewSuiteName) ?? .standard
        defaults.removePersistentDomain(forName: previewSuiteName)
        let service = DeterministicMusicService(library: library, playback: playback)
        let model = AppModel(
            library: service,
            playbackTransport: service,
            // An in-memory store for a fixed schema fails only on a programming error.
            modelContainer: try! AppComposition.makeModelContainer(storedInMemoryOnly: true),
            libraryPreferences: LibraryPreferences(defaults: defaults),
            savedAlgorithm: SavedShuffleAlgorithm(defaults: defaults),
            lastFMTransport: nil,
            artworkStore: nil
        )
        try? model.sessionDraft.add(Array(draft.prefix(model.sessionDraft.capacity)))
        return model
    }

    private static let previewSuiteName = "com.joshuahughes.shuffled.preview"
}
