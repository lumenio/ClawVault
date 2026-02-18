// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClawVaultCompanion",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClawVaultCompanion",
            path: "ClawVaultCompanion",
            exclude: ["Resources/Info.plist", "Resources/ClawVaultCompanion.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
