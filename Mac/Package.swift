// swift-tools-version: 6.0
import PackageDescription

let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "Doumi",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
    ],
    targets: [
        // Shared engine — used by both CLI and GUI
        .target(
            name: "DoumiCore",
            dependencies: [.product(name: "Yams", package: "Yams")],
            path: "Sources/DoumiCore",
            swiftSettings: upcomingFeatures
        ),

        // CLI tool: `doumi`
        .executableTarget(
            name: "doumi",
            dependencies: [
                "DoumiCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/doumi",
            swiftSettings: upcomingFeatures
        ),

        // GUI app: `DoumiApp`
        .executableTarget(
            name: "DoumiApp",
            dependencies: ["DoumiCore"],
            path: "Sources/DoumiApp",
            swiftSettings: upcomingFeatures
        ),
    ],
    swiftLanguageModes: [.v6]
)
