// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Hablamon",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "hablamon", targets: ["HablamonCLI"]),
        .executable(name: "HablamonApp", targets: ["HablamonApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
        .package(url: "https://github.com/ajevans99/swift-json-schema", from: "0.14.0"),
        // Qwen3-TTS voice cloning on MLX. Young and tracks main, so pinned to a tested commit.
        .package(url: "https://github.com/soniqo/speech-swift", revision: "9ce78eaec038b4dc8b519a8b01ecb4059549cfec"),
    ],
    targets: [
        .target(
            name: "HablamonModels",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
            ]
        ),
        .target(
            name: "HablamonCore",
            dependencies: ["HablamonModels"],
            resources: [
                .copy("Resources/characters.default.json"), .copy("Resources/profiles"),
                .copy("Resources/dictionary"),
                .copy("Resources/game-terms"),
            ]
        ),
        .executableTarget(
            name: "HablamonCLI",
            dependencies: [
                "HablamonCore",
                "HablamonModels",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "HablamonVoices",
            dependencies: [
                "HablamonCore",
                "HablamonModels",
                .product(name: "Qwen3TTS", package: "speech-swift", condition: .when(platforms: [.macOS])),
                .product(name: "AudioCommon", package: "speech-swift", condition: .when(platforms: [.macOS])),
            ],
            resources: [.copy("Resources/voices")]
        ),
        .executableTarget(
            name: "HablamonApp",
            dependencies: ["HablamonCore", "HablamonVoices"]
        ),
        .testTarget(
            name: "HablamonModelsTests",
            dependencies: ["HablamonModels"]
        ),
        .testTarget(
            name: "HablamonCoreTests",
            dependencies: ["HablamonCore", "HablamonModels"]
        ),
        .testTarget(
            name: "HablamonVoicesTests",
            dependencies: ["HablamonVoices", "HablamonCore", "HablamonModels"]
        ),
    ]
)
