// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LinkGuardTL",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .executable(name: "LinkGuardTL", targets: ["LinkGuardTL"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LinkGuardTL",
            dependencies: []
        )
    ]
)