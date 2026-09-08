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
  dependencies: [
    .package(url: "https://github.com/sbooth/CSpeex", exact: "1.2.1")
  ],
  targets: [
    .executableTarget(
      name: "VhraseApp",
      dependencies: [.product(name: "speex", package: "CSpeex")],
      path: "Sources/VhraseApp",
      resources: [
        .copy("UI/Resources/ProviderIcons")
      ]
    )
  ]
)
