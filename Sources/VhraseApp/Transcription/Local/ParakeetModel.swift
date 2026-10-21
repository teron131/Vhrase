// Describes NVIDIA Parakeet's files to the setup store: FluidAudio downloads and compiles them, and a completion marker separates a finished download from an interrupted one.

import FluidAudio
import Foundation

struct ParakeetModel: LocalModel {
  /// The Hugging Face repository of the Core ML model FluidAudio downloads and loads as its version 3.
  static let repository = Repo.parakeetV3.rawValue
  /// FluidAudio stores each repository under its own folder name, so Vhrase uses the same name inside its Models folder.
  static let defaultDirectory = LocalModelFiles.directory
    .appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)

  let title = STTProvider.parakeet.title
  /// FluidAudio's int8 Parakeet TDT 0.6B v3 bundles, measured on Hugging Face on 2026-10-09.
  let downloadSizeLabel: String? = "480 MB"
  /// Covers the download plus Core ML's compiled copy.
  let requiredFreeBytes: Int64? = 1_200_000_000
  let loadingNote = "The first time after a download or macOS update takes about 15 seconds."
  private let directory: URL
  private let parakeet: ParakeetRecognizer

  init(directory: URL = ParakeetModel.defaultDirectory) {
    self.directory = directory
    parakeet = ParakeetRecognizer(directory: directory)
  }

  var recognizer: any SpeechToTextClient {
    parakeet
  }

  var isInstalled: Bool {
    FileManager.default.fileExists(
      atPath: LocalModelFiles.completionMarker(in: directory).path)
      && AsrModels.modelsExist(at: directory, version: .v3)
  }

  func download(
    progress: @escaping @Sendable (_ fraction: Double, _ isIndeterminate: Bool) -> Void
  ) async throws {
    do {
      // A folder without the completion marker is an interrupted download, so start it over.
      try await AsrModels.download(to: directory, force: true, version: .v3) { update in
        let isCompiling =
          switch update.phase {
          case .listing, .downloading: false
          case .compiling: true
          }
        progress(update.fractionCompleted, isCompiling)
      }
      try Task.checkCancellation()
      try Data().write(to: LocalModelFiles.completionMarker(in: directory))
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  func load() async throws {
    try await parakeet.load()
  }

  func remove() async throws {
    await parakeet.unload()
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
}
