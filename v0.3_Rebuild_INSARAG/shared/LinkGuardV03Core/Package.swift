// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LinkGuardV03Core",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LinkGuardV03Core",
            targets: ["LinkGuardV03Core"]
        ),
        .library(
            name: "LinkGuardV03MacUI",
            targets: ["LinkGuardV03MacUI"]
        ),
        .library(
            name: "LinkGuardV03FieldUI",
            targets: ["LinkGuardV03FieldUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.18.0")
    ],
    targets: [
        .target(name: "LinkGuardV03Core"),
        .target(
            name: "LinkGuardV03MacUI",
            dependencies: [
                "LinkGuardV03Core",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .target(
            name: "LinkGuardV03FieldUI",
            dependencies: ["LinkGuardV03Core"]
        ),
        .testTarget(
            name: "LinkGuardV03CoreTests",
            dependencies: ["LinkGuardV03Core", "LinkGuardV03MacUI", "LinkGuardV03FieldUI"]
        )
    ]
)
