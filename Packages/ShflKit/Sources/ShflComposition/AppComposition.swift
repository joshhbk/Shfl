import Foundation
import ShflAppleMusic
import ShflCore
import ShflDeterministic
import ShflLastFM
import SwiftData

/// The single place where Shfl chooses concrete adapters and storage.
@MainActor
public struct AppComposition {
    public enum Mode: Equatable {
        case live
        case deterministic
    }

    static let deterministicLaunchArgument = "--deterministic"

    public let mode: Mode
    public let appModel: AppModel
    /// Deterministic launches get a fresh suite, so they always start from the same settings.
    public let userDefaults: UserDefaults

    static func selectedMode(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Mode {
        if arguments.contains(deterministicLaunchArgument)
            || environment["XCTestConfigurationFilePath"] != nil {
            return .deterministic
        }
        return .live
    }

    public static func make() throws -> AppComposition {
        try make(mode: selectedMode())
    }

    static func make(mode: Mode) throws -> AppComposition {
        switch mode {
        case .live:
            let defaults = UserDefaults.standard
            let modelContainer = try makeModelContainer(storedInMemoryOnly: false)
            return AppComposition(
                mode: mode,
                appModel: AppModel(
                    library: AppleMusicService(),
                    playbackTransport: MusicKitTransport(),
                    modelContainer: modelContainer,
                    libraryPreferences: LibraryPreferences(defaults: defaults),
                    savedAlgorithm: SavedShuffleAlgorithm(defaults: defaults),
                    lastFMTransport: LastFMTransport(
                        apiKey: LastFMConfig.apiKey,
                        sharedSecret: LastFMConfig.sharedSecret
                    ),
                    artworkStore: ArtworkStore()
                ),
                userDefaults: defaults
            )

        case .deterministic:
            let defaults = isolatedDefaults()
            let libraryPreferences = LibraryPreferences(defaults: defaults)
            libraryPreferences.autofillAlgorithm = .random
            let savedAlgorithm = SavedShuffleAlgorithm(defaults: defaults)
            savedAlgorithm.save(.weightedByPlayCount)

            let musicService = DeterministicMusicService(library: .launch)
            return AppComposition(
                mode: mode,
                appModel: AppModel(
                    library: musicService,
                    playbackTransport: musicService,
                    modelContainer: try makeModelContainer(storedInMemoryOnly: true),
                    libraryPreferences: libraryPreferences,
                    savedAlgorithm: savedAlgorithm,
                    lastFMTransport: nil,
                    artworkStore: nil
                ),
                userDefaults: defaults
            )
        }
    }

    static func makeModelContainer(storedInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = Schema([PersistedSession.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: storedInMemoryOnly)]
        )
    }

    static func isolatedDefaults() -> UserDefaults {
        let suiteName = "com.joshuahughes.shuffled.deterministic.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
