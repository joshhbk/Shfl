import Foundation
import ShflCore
import SwiftData

/// The single place where Shfl chooses concrete adapters and storage.
@MainActor
struct AppComposition {
    enum Mode: Equatable {
        case live
        case deterministic
    }

    static let deterministicLaunchArgument = "--deterministic"

    let modelContainer: ModelContainer
    let libraryPreferences: LibraryPreferences
    let appearanceSettings: AppearanceSettings
    let appModel: AppModel
    let artworkStore: ArtworkStore?
    let showsStartupSplash: Bool

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

    static func make() throws -> AppComposition {
        try make(mode: selectedMode())
    }

    static func make(mode: Mode) throws -> AppComposition {
        let schema = Schema([
            PersistedSession.self
        ])

        switch mode {
        case .live:
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
            let libraryPreferences = LibraryPreferences()
            return AppComposition(
                modelContainer: modelContainer,
                libraryPreferences: libraryPreferences,
                appearanceSettings: AppearanceSettings(),
                appModel: AppModel(
                    library: AppleMusicService(),
                    playbackTransport: MusicKitTransport(),
                    modelContext: modelContainer.mainContext,
                    libraryPreferences: libraryPreferences,
                    savedAlgorithm: SavedShuffleAlgorithm()
                ),
                artworkStore: ArtworkStore(),
                showsStartupSplash: true
            )

        case .deterministic:
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let defaults = isolatedDefaults()
            let libraryPreferences = LibraryPreferences(defaults: defaults)
            libraryPreferences.autofillAlgorithm = .random
            let appearanceSettings = AppearanceSettings(defaults: defaults)
            appearanceSettings.currentThemeId = "silver"
            let savedAlgorithm = SavedShuffleAlgorithm(defaults: defaults)
            savedAlgorithm.save(.weightedByPlayCount)

            let musicService = DeterministicMusicService(
                configuration: .init(
                    librarySongs: deterministicSongs,
                    libraryPlaylists: deterministicPlaylists,
                    playlistSongs: ["scenario-playlist": deterministicSongs],
                    playbackDuration: 180
                )
            )
            return AppComposition(
                modelContainer: modelContainer,
                libraryPreferences: libraryPreferences,
                appearanceSettings: appearanceSettings,
                appModel: AppModel(
                    library: musicService,
                    playbackTransport: musicService,
                    modelContext: modelContainer.mainContext,
                    libraryPreferences: libraryPreferences,
                    savedAlgorithm: savedAlgorithm,
                    scrobblingEnabled: false
                ),
                artworkStore: nil,
                showsStartupSplash: false
            )
        }
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "com.joshuahughes.shuffled.deterministic.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static let deterministicSongs = [
        Song(
            id: "scenario-low-tide",
            title: "Low Tide",
            artist: "Harbour Lights",
            albumTitle: "Deterministic Sessions",
            artworkURL: nil,
            playCount: 0
        ),
        Song(
            id: "scenario-second-wind",
            title: "Second Wind",
            artist: "Northern Static",
            albumTitle: "Deterministic Sessions",
            artworkURL: nil,
            playCount: 1
        ),
        Song(
            id: "scenario-afterglow",
            title: "Afterglow",
            artist: "Paper Satellites",
            albumTitle: "Deterministic Sessions",
            artworkURL: nil,
            playCount: 2
        )
    ]

    private static let deterministicPlaylists = [
        Playlist(id: "scenario-playlist", name: "Deterministic Sessions")
    ]
}
