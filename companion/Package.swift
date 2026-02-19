// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonolithCompanion",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MonolithCompanion",
            path: "MonolithCompanion",
            exclude: ["Resources/Info.plist", "Resources/MonolithCompanion.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
