// Owns the Parakeet model on this Mac: whether its files are complete, the one-time download, background preparation, and removal.

import FluidAudio
import Foundation
import OSLog

/// Publishes Parakeet's setup state; downloading is the only step of on-device recognition that uses the network.
@MainActor
final class ParakeetModelStore: ObservableObject {
  enum State: Equatable {
    case missing
    /// `isCompiling` marks Core ML compiling the downloaded model for this Mac, which follows the transfer.
    case downloading(fraction: Double, isCompiling: Bool)
    case installed
    case failed(String)

    /// Words download progress identically wherever it appears.
    static func progressTitle(fraction: Double, isCompiling: Bool) -> String {
      isCompiling
        ? "Preparing for this Mac…"
        : "Downloading \(fraction.formatted(.percent.precision(.fractionLength(0))))…"
    }
  }

  /// FluidAudio's int8 Parakeet TDT 0.6B v3 bundles, measured on Hugging Face on 2026-10-09.
  static let downloadSizeLabel = "480 MB"
  /// Covers the download plus Core ML's compiled copy, so preparation cannot exhaust the disk partway through.
  private nonisolated static let requiredFreeBytes: Int64 = 1_200_000_000
  private nonisolated static let completionMarkerName = ".vhrase-complete"

  /// FluidAudio stores each repository under its own folder name, so Vhrase uses the same name inside its Models folder.
  nonisolated static let defaultDirectory: URL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Vhrase/Models", isDirectory: true)
    .appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)

  let directory: URL
  /// Runs the downloaded model; it reads only these files and never downloads.
  let recognizer: ParakeetRecognizer
  @Published private(set) var state: State
  /// True while the model loads in the background; the first load per app and macOS version includes Core ML's compile.
  @Published private(set) var isPreparing = false
  private var downloadTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "Parakeet")

  init(directory: URL = ParakeetModelStore.defaultDirectory) {
    self.directory = directory
    recognizer = ParakeetRecognizer(directory: directory)
    state = Self.isComplete(at: directory) ? .installed : .missing
  }

  var isInstalled: Bool {
    state == .installed
  }

  var isDownloading: Bool {
    downloadTask != nil
  }

  /// Fetches the model from FluidAudio's Hugging Face repository and lets Core ML prepare it, replacing any interrupted copy.
  func download() {
    guard downloadTask == nil, !isInstalled else { return }
    state = .downloading(fraction: 0, isCompiling: false)
    let directory = directory
    // The store lives as long as AppState, so the transfer may hold it until the download ends.
    downloadTask = Task.detached(priority: .userInitiated) {
      let started = ContinuousClock.now
      // FluidAudio reports every received network chunk; forwarding only whole-percent and phase changes spares AppState's observers thousands of redraws.
      let lastProgress = OSAllocatedUnfairLock<State?>(initialState: nil)
      let outcome: State
      do {
        try Self.checkFreeSpace(near: directory)
        // A folder without the completion marker is an interrupted download, so start it over.
        try await AsrModels.download(to: directory, force: true, version: .v3) { progress in
          let update = Self.downloadState(for: progress)
          let isNew = lastProgress.withLock { last in
            defer { last = update }
            return last != update
          }
          guard isNew else { return }
          Task { @MainActor in
            self.report(update)
          }
        }
        try Task.checkCancellation()
        try Data().write(to: directory.appendingPathComponent(Self.completionMarkerName))
        outcome = .installed
      } catch {
        outcome = Task.isCancelled ? .missing : .failed(Self.failureMessage(for: error))
      }
      let seconds = started.duration(to: .now) / .seconds(1)
      await self.finishDownload(outcome, seconds: seconds)
    }
  }

  /// Stops the transfer at FluidAudio's next cancellation point; partial files are removed when it ends.
  func cancelDownload() {
    downloadTask?.cancel()
  }

  /// Loads the installed model in the background so a dictation does not wait for Core ML's one-time compile.
  func prepare() {
    guard isInstalled, !isPreparing else { return }
    isPreparing = true
    Task {
      do {
        try await recognizer.load()
      } catch {
        // Transcription reports the failure to the user; the log keeps its cause for diagnosis.
        let failure = error as NSError
        logger.error(
          "Model load failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      }
      isPreparing = false
    }
  }

  /// Releases the loaded model before deleting its files so no later dictation reads a removed bundle.
  func remove() async throws {
    guard downloadTask == nil else { return }
    await recognizer.unload()
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    state = .missing
  }

  private func report(_ update: State) {
    guard downloadTask != nil else { return }
    state = update
  }

  private func finishDownload(_ outcome: State, seconds: Double) {
    downloadTask = nil
    if outcome != .installed {
      try? FileManager.default.removeItem(at: directory)
    }
    state = outcome
    let result =
      switch outcome {
      case .installed: "installed"
      case .missing: "cancelled"
      case .failed, .downloading: "failed"
      }
    logger.notice(
      "Model download \(result, privacy: .public) seconds=\(seconds, format: .fixed(precision: 1))")
  }

  /// Rounds to whole percents so repeated network chunks within one percent produce the same state.
  private nonisolated static func downloadState(for progress: DownloadProgress) -> State {
    let isCompiling =
      switch progress.phase {
      case .listing, .downloading: false
      case .compiling: true
      }
    let percent = (min(max(progress.fractionCompleted, 0), 1) * 100).rounded(.down)
    return .downloading(fraction: percent / 100, isCompiling: isCompiling)
  }

  private nonisolated static func isComplete(at directory: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent(completionMarkerName).path)
      && AsrModels.modelsExist(at: directory, version: .v3)
  }

  private nonisolated static func checkFreeSpace(near directory: URL) throws {
    let modelsFolder = directory.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true)
    let available =
      try modelsFolder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage ?? .max
    guard available >= requiredFreeBytes else {
      let formatter = ByteCountFormatter()
      throw ParakeetModelError.insufficientSpace(
        available: formatter.string(fromByteCount: available),
        required: formatter.string(fromByteCount: requiredFreeBytes)
      )
    }
  }

  private nonisolated static func failureMessage(for error: Error) -> String {
    if let urlError = error as? URLError,
      [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut]
        .contains(urlError.code)
    {
      return
        "Couldn't reach Hugging Face. Connect to the internet for the one-time download; Parakeet then works offline."
    }
    return error.localizedDescription
  }
}

private enum ParakeetModelError: LocalizedError {
  case insufficientSpace(available: String, required: String)

  var errorDescription: String? {
    switch self {
    case .insufficientSpace(let available, let required):
      "Parakeet needs about \(required) free to download and prepare; \(available) is available."
    }
  }
}
