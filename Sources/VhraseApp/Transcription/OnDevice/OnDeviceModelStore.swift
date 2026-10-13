// Owns one on-device model's setup on this Mac: whether its files are complete, the one-time download, background preparation, and removal.

import Foundation
import OSLog

/// Publishes a model's setup state; downloading is the only step of on-device recognition that uses the network.
@MainActor
final class OnDeviceModelStore: ObservableObject {
  enum State: Equatable {
    case missing
    /// `isIndeterminate` marks setup work without a percentage: building a runtime before the transfer, or compiling and loading the model for this Mac after it.
    case downloading(fraction: Double, isIndeterminate: Bool)
    case installed
    case failed(String)

    /// Words download progress identically wherever it appears.
    static func progressTitle(fraction: Double, isIndeterminate: Bool) -> String {
      isIndeterminate
        ? "Preparing for this Mac…"
        : "Downloading \(fraction.formatted(.percent.precision(.fractionLength(0))))…"
    }
  }

  /// The model this store sets up; Hugging Face's changes with the model named in settings.
  @Published private(set) var model: any OnDeviceModel
  @Published private(set) var state: State
  private var downloadTask: Task<Void, Never>?
  @Published private var preparationTask: Task<Void, Never>?
  /// Identifies the download whose progress and outcome may still change `state`.
  private var downloadID: UUID?
  /// Invalidates removal completions when the selected model changes.
  private var selectionID = UUID()

  init(model: any OnDeviceModel) {
    self.model = model
    state = model.isInstalled ? .installed : .missing
  }

  var isInstalled: Bool {
    state == .installed
  }

  var isDownloading: Bool {
    downloadTask != nil
  }

  /// True while the model loads in the background, including Core ML's first-load compilation; the task is the source of truth for preparation state.
  var isPreparing: Bool {
    preparationTask != nil
  }

  /// Words the download action with the model's measured size when there is one.
  var downloadTitle: String {
    model.downloadSizeLabel.map { "Download \($0)" } ?? "Download"
  }

  /// Points the store at another model of the same family, abandoning a download of the previous one.
  func select(_ model: any OnDeviceModel) {
    cancelPreparation()
    downloadTask?.cancel()
    downloadTask = nil
    downloadID = nil
    selectionID = UUID()
    self.model = model
    state = model.isInstalled ? .installed : .missing
  }

  /// Fetches the model from Hugging Face and lets its runtime prepare it, replacing any interrupted copy.
  func download() {
    guard downloadTask == nil, !isInstalled else { return }
    state = .downloading(fraction: 0, isIndeterminate: false)
    let model = model
    let id = UUID()
    downloadID = id
    // The store lives as long as AppState, so the transfer may hold it until the download ends.
    downloadTask = Task.detached(priority: .userInitiated) {
      let started = ContinuousClock.now
      // Runtimes report every received network chunk; forwarding only whole-percent and phase changes spares AppState's observers thousands of redraws.
      let lastProgress = OSAllocatedUnfairLock<State?>(initialState: nil)
      let outcome: State
      do {
        try Self.checkFreeSpace(for: model)
        try await model.download { fraction, isIndeterminate in
          let percent = (min(max(fraction, 0), 1) * 100).rounded(.down)
          let update = State.downloading(fraction: percent / 100, isIndeterminate: isIndeterminate)
          let isNew = lastProgress.withLock { last in
            defer { last = update }
            return last != update
          }
          guard isNew else { return }
          Task { @MainActor in
            self.report(update, from: id)
          }
        }
        outcome = .installed
      } catch {
        outcome =
          Task.isCancelled ? .missing : .failed(Self.failureMessage(for: error, model: model))
      }
      let seconds = started.duration(to: .now) / .seconds(1)
      await self.finishDownload(outcome, of: model, id: id, seconds: seconds)
    }
  }

  /// Stops the transfer at the runtime's next cancellation point; partial files are removed when it ends.
  func cancelDownload() {
    downloadTask?.cancel()
  }

  /// Loads the installed model in the background so a dictation does not wait for it.
  func prepare() {
    guard isInstalled, !isPreparing else { return }
    let model = model
    preparationTask = Task {
      do {
        try await model.load()
      } catch  where Task.isCancelled {
        return
      } catch {
        // Transcription reports the failure to the user; the log keeps its cause for diagnosis.
        let failure = error as NSError
        Self.logger(for: model).error(
          "Model load failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      }
      guard !Task.isCancelled else { return }
      preparationTask = nil
    }
  }

  /// Stops a warm-up that no longer serves the selected provider, preventing a queued task from starting a new helper later.
  func cancelPreparation() {
    preparationTask?.cancel()
    preparationTask = nil
  }

  func remove() async throws {
    guard downloadTask == nil, !isPreparing else { return }
    let id = selectionID
    try await model.remove()
    guard selectionID == id else { return }
    state = .missing
  }

  private func report(_ update: State, from id: UUID) {
    guard downloadID == id else { return }
    state = update
  }

  private func finishDownload(
    _ outcome: State, of model: any OnDeviceModel, id: UUID, seconds: Double
  ) {
    let result =
      switch outcome {
      case .installed: "installed"
      case .missing: "cancelled"
      case .failed, .downloading: "failed"
      }
    Self.logger(for: model).notice(
      "Model download \(result, privacy: .public) seconds=\(seconds, format: .fixed(precision: 1))")
    // A download abandoned by `select` must not report against the model chosen since.
    guard downloadID == id else { return }
    downloadID = nil
    downloadTask = nil
    state = outcome
  }

  private nonisolated static func logger(for model: any OnDeviceModel) -> Logger {
    Logger(subsystem: "local.codex.Vhrase", category: model.title)
  }

  /// Refuses a download that would exhaust the disk partway through; models of unknown size skip the check.
  private nonisolated static func checkFreeSpace(for model: any OnDeviceModel) throws {
    guard let required = model.requiredFreeBytes else { return }
    let modelsFolder = OnDeviceModelFiles.directory
    try FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true)
    let available =
      try modelsFolder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage ?? .max
    guard available >= required else {
      let formatter = ByteCountFormatter()
      throw OnDeviceModelError.insufficientSpace(
        title: model.title,
        available: formatter.string(fromByteCount: available),
        required: formatter.string(fromByteCount: required)
      )
    }
  }

  private nonisolated static func failureMessage(
    for error: Error, model: any OnDeviceModel
  ) -> String {
    if let urlError = error as? URLError,
      [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut]
        .contains(urlError.code)
    {
      return
        "Couldn't reach Hugging Face. Connect to the internet for the one-time download; \(model.title) then works offline."
    }
    return error.localizedDescription
  }
}

private enum OnDeviceModelError: LocalizedError {
  case insufficientSpace(title: String, available: String, required: String)

  var errorDescription: String? {
    switch self {
    case .insufficientSpace(let title, let available, let required):
      "\(title) needs about \(required) free to download and prepare; \(available) is available."
    }
  }
}
