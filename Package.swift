// swift-tools-version: 6.2
// Builds the native menu-bar executable, ships its provider marks and Hugging Face helper script as SwiftPM resources, and compiles FluidAudio in for local Parakeet recognition.

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
    .package(url: "https://github.com/sbooth/CSpeex", exact: "1.2.1"),
    // Empty traits drop FluidAudio's prebuilt NeMo text-normalization library, which speech recognition does not use.
    .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.1", traits: []),
  ],
  targets: [
    .executableTarget(
      name: "VhraseApp",
      dependencies: [
        .product(name: "speex", package: "CSpeex"),
        .product(name: "FluidAudio", package: "FluidAudio"),
      ],
      path: "Sources/VhraseApp",
      resources: [
        .copy("UI/Resources/ProviderIcons"),
        // The Python script and its uv lockfile that run Hugging Face models; uv builds the environment on the user's Mac.
        // Each file is named so that nothing else left in that folder, such as an editor's cache, is packaged with them.
        .copy("Transcription/Local/HuggingFaceRuntime/asr.py"),
        .copy("Transcription/Local/HuggingFaceRuntime/asr.py.lock"),
      ]
    )
  ]
)
