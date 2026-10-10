// swift-tools-version: 6.2
import PackageDescription

/// Mirrors the app target's settings (SWIFT_APPROACHABLE_CONCURRENCY turns on
/// the last five), so code keeps its isolation when it moves into the package.
/// Change both together.
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

/// No default isolation, matching ShflTests.
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
    ],
    targets: [
        /// May import only Foundation, Observation and SwiftData; the compiler
        /// doesn't enforce that, scripts/check-core-imports.sh does.
        .target(
            name: "ShflCore",
            swiftSettings: librarySettings
        ),
        .testTarget(
            name: "ShflCoreTests",
            dependencies: ["ShflCore"],
            swiftSettings: testSettings
        ),
    ]
)
