// swift-tools-version: 6.0
// Defines the SwiftPM macOS executable package for Vhrase.

import PackageDescription

let package = Package(
    name: "Vhrase",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Vhrase",
            targets: ["VhraseApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VhraseApp",
            path: "Sources/VhraseApp"
        )
    ]
)
