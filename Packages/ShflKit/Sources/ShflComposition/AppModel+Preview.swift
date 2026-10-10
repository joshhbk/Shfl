import Foundation
import ShflCore
import ShflDeterministic

extension AppModel {
    /// A model for previews and view tests. It browses and plays `library`
    /// without Apple Music, starts with `draft` in the session draft, and has
    /// no saved session, Last.fm or artwork. Its settings live in a preview
    /// suite that is emptied each time a preview model is made, so nothing
    /// leaks into the app's settings or piles up between runs.
    ///
    /// Lives here rather than in ShflDeterministic, which composition
    /// depends on, so it can build an `AppModel`.
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
