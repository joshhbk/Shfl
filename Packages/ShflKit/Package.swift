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
        .target(
            name: "ShflAppleMusicUI",
            dependencies: ["ShflCore", "ShflAppleMusic"],
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflAppleMusicUITests",
            dependencies: ["ShflAppleMusicUI", "ShflAppleMusic", "ShflCore"],
            swiftSettings: testSettings
        ),
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
        .target(
            name: "ShflComposition",
            dependencies: ["ShflCore", "ShflAppleMusic", "ShflLastFM", "ShflDeterministic"],
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflCompositionTests",
            dependencies: ["ShflComposition", "ShflCore", "ShflDeterministic", "ShflLastFM", "ShflTestSupport"],
            swiftSettings: testSettings
        ),
        .target(
            name: "ShflTestSupport",
            swiftSettings: testSettings
        ),
    ]
)
