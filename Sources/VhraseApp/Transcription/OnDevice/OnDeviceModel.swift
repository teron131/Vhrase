// Describes one downloadable speech model to the setup store: how its runtime fetches, loads, and removes the files, and what recognizes speech with them.

import Foundation

protocol OnDeviceModel: Sendable {
  var title: String { get }
  /// The measured download size, or `nil` for a model Vhrase has not measured.
  var downloadSizeLabel: String? { get }
  /// Free space the download and whatever its runtime adds beside it need, or `nil` when the size is unknown.
  var requiredFreeBytes: Int64? { get }
  /// A sentence on how long loading takes and when, shown while the model prepares.
  var loadingNote: String { get }
  var recognizer: any SpeechToTextClient { get }
  /// Reads only local files: true once a download finished and wrote its completion marker.
  var isInstalled: Bool { get }

  /// Fetches the files, proves the runtime can load them, and writes the completion marker; a failed or cancelled download removes its partial files before throwing.
  func download(
    progress: @escaping @Sendable (_ fraction: Double, _ isIndeterminate: Bool) -> Void
  ) async throws
  /// Loads the installed model ahead of a dictation; it never downloads.
  func load() async throws
  /// Releases the loaded model before deleting its files, so no later dictation reads a removed bundle.
  func remove() async throws
}

enum OnDeviceModelFiles {
  /// The file that marks a model folder's download as finished; a folder without it is an interrupted download, replaced rather than loaded.
  static func completionMarker(in modelDirectory: URL) -> URL {
    modelDirectory.appendingPathComponent(".vhrase-complete")
  }

  static let directory: URL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Vhrase/Models", isDirectory: true)
}
