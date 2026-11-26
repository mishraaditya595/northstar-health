// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BeyondRepWatchCore",
    platforms: [.watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "BeyondRepWatchCore", targets: ["BeyondRepWatchCore"]),
    ],
    targets: [
        .target(name: "BeyondRepWatchCore"),
        .testTarget(
            name: "BeyondRepWatchCoreTests",
            dependencies: ["BeyondRepWatchCore"]
        ),
    ]
)
