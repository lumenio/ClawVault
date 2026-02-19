// swift-tools-version: 6.0
// Requires Xcode 16+ or Swift 6.0+ toolchain (for swift-testing framework).
import PackageDescription

let package = Package(
    name: "MonolithDaemon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MonolithDaemon",
            path: "Sources/MonolithDaemon",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MonolithDaemonTests",
            dependencies: ["MonolithDaemon"],
            path: "Tests/MonolithDaemonTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
