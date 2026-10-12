// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Hablamon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "hablamon", targets: ["HablamonCLI"]),
        .executable(name: "HablamonApp", targets: ["HablamonApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
        .package(url: "https://github.com/ajevans99/swift-json-schema", from: "0.14.0"),
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
            resources: [.copy("Resources/characters.default.json")]
        ),
        .executableTarget(
            name: "HablamonCLI",
            dependencies: [
                "HablamonCore",
                "HablamonModels",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "HablamonApp",
            dependencies: ["HablamonCore"]
        ),
        .testTarget(
            name: "HablamonModelsTests",
            dependencies: ["HablamonModels"]
        ),
        .testTarget(
            name: "HablamonCoreTests",
            dependencies: ["HablamonCore", "HablamonModels"]
        ),
    ]
)
