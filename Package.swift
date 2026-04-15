// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoTap",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "AutoTapCore", targets: ["AutoTapCore"]),
        .executable(name: "AutoTap", targets: ["AutoTap"]),
    ],
    targets: [
        .target(name: "AutoTapCore"),
        .executableTarget(
            name: "AutoTap",
            dependencies: ["AutoTapCore"],
            path: "Sources/AutoTapApp"
        ),
        .testTarget(
            name: "AutoTapCoreTests",
            dependencies: ["AutoTapCore"]
        ),
    ]
)
