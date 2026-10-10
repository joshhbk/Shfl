import Foundation
import ShflCore
import ShflDeterministic

extension AppModel {
    /// A model for previews and view tests. It browses and plays `library`
    /// without Apple Music, starts with `draft` in the session draft, and has
    /// no saved session, Last.fm or artwork. Its settings are its own, so
    /// nothing it does leaks into the app's.
    ///
    /// Lives here rather than in ShflDeterministic, which composition
    /// depends on, so it can build an `AppModel`.
    public static func preview(
        library: DeterministicLibrary = .sample,
        playback: DeterministicPlayback = DeterministicPlayback(),
        draft: [Song] = []
    ) -> AppModel {
        let suiteName = "com.joshuahughes.shuffled.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
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
}
