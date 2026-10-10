// swift-tools-version: 6.2
import PackageDescription

// Must match the app target's Swift settings, so moved code keeps its isolation.
let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let librarySettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
] + upcomingFeatures

let testSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
] + upcomingFeatures

let package = Package(
    name: "ShflKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS("26.2"),
    ],
    products: [
        .library(name: "ShflCore", targets: ["ShflCore"]),
        .library(name: "ShflAppleMusicUI", targets: ["ShflAppleMusicUI"]),
        .library(name: "ShflComposition", targets: ["ShflComposition"]),
        .library(name: "ShflDeterministic", targets: ["ShflDeterministic"]),
        .library(name: "ShflLastFM", targets: ["ShflLastFM"]),
    ],
    targets: [
        // Foundation, Observation and SwiftData only; scripts/check-core-imports.sh enforces it.
        .target(
            name: "ShflCore",
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflCoreTests",
            dependencies: ["ShflCore", "ShflDeterministic", "ShflTestSupport"],
            swiftSettings: testSettings
        ),
        /// An in-memory library and transport for tests, previews and
        /// `--deterministic` launches.
        .target(
            name: "ShflDeterministic",
            dependencies: ["ShflCore"],
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflDeterministicTests",
            dependencies: ["ShflDeterministic"],
            swiftSettings: testSettings
        ),
        /// The MusicKit adapters: library catalog, playback transport and
        /// artwork lookup.
        .target(
            name: "ShflAppleMusic",
            dependencies: ["ShflCore"],
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflAppleMusicTests",
            dependencies: ["ShflAppleMusic", "ShflDeterministic", "ShflTestSupport"],
            swiftSettings: testSettings
        ),
        /// SwiftUI views that draw Apple Music artwork. The only views in the
        /// package; every shell draws artwork through them.
        .target(
            name: "ShflAppleMusicUI",
            dependencies: ["ShflCore", "ShflAppleMusic"],
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflAppleMusicUITests",
            dependencies: ["ShflAppleMusicUI"],
            swiftSettings: testSettings
        ),
        /// Scrobbling to Last.fm and the listener's Last.fm account.
        .target(
            name: "ShflLastFM",
            dependencies: ["ShflCore"],
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflLastFMTests",
            dependencies: ["ShflLastFM"],
            swiftSettings: testSettings
        ),
        /// Chooses each launch's adapters and hands shells one AppModel.
        .target(
            name: "ShflComposition",
            dependencies: ["ShflCore", "ShflAppleMusic", "ShflLastFM", "ShflDeterministic"],
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflCompositionTests",
            dependencies: ["ShflComposition", "ShflTestSupport"],
            swiftSettings: testSettings
        ),
        /// Helpers shared by the test targets. No product, so nothing ships it.
        .target(
            name: "ShflTestSupport",
            swiftSettings: testSettings
        ),
    ]
)
