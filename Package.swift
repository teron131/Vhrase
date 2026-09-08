// swift-tools-version: 6.0
// Builds the native menu-bar executable and ships its provider marks as SwiftPM resources.

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
      path: "Sources/VhraseApp",
      resources: [
        .copy("UI/Resources/ProviderIcons")
      ]
    )
  ]
)
