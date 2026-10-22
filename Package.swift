// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PokeTokenBar",
            path: "Sources/PokeTokenBar",
            resources: [.copy("Resources/BattleText"), .copy("Resources/BattleEffects"), .copy("Resources/Showmotion"), .copy("Resources/PokeRogue"), .copy("Resources/PokeRoguePlayer")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarTests",
            resources: [
                .copy("Fixtures/PokeRoguePreview"),
                .copy("Fixtures/PokeRogueFaithful"),
                .copy("Fixtures/CodexFork"),
                .copy("Fixtures/CodexSubagent"),
            ]
        ),
    ]
)
