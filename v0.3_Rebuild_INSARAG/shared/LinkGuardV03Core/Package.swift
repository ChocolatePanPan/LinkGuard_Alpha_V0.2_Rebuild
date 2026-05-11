// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LinkGuardV03Core",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "LinkGuardV03Core",
            targets: ["LinkGuardV03Core"]
        )
    ],
    targets: [
        .target(name: "LinkGuardV03Core"),
        .testTarget(
            name: "LinkGuardV03CoreTests",
            dependencies: ["LinkGuardV03Core"]
        )
    ]
)
