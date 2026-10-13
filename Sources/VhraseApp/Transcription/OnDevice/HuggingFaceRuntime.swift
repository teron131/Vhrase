// Starts the bundled Hugging Face helper through uv and names where its models live, so setup and recognition share one launch recipe and one cache.

import Foundation

/// The Python side of Hugging Face recognition: uv builds the environment the script declares, and both the script and the Hub cache sit inside Vhrase's Models folder.
enum HuggingFaceRuntime {
  private static let directory = OnDeviceModelFiles.directory
    .appendingPathComponent("huggingface", isDirectory: true)
  /// The Hub client's cache, kept apart from `~/.cache/huggingface` so Vhrase alone decides what is installed and removing a model never affects another tool.
  static let cacheDirectory = directory.appendingPathComponent("hub", isDirectory: true)
  /// Where the bundled script runs from; uv keys its environment to the script's path, so a path that survives app rebuilds and moves means one environment instead of a new one each time.
  private static let scriptDirectory = directory.appendingPathComponent(
    "runtime", isDirectory: true)

  static func modelDirectory(for reference: HuggingFaceModelReference) -> URL {
    cacheDirectory.appendingPathComponent(reference.cacheFolderName, isDirectory: true)
  }

  /// Starts one of the script's commands with its output piped back; only a download may ask the Hub for files.
  ///
  /// uv reuses the environment it built for the script's locked dependencies, so a later start reads only its own cache.
  static func start(_ arguments: [String], allowsModelDownload: Bool) throws -> HuggingFaceProcess {
    guard let uv = uvURL() else {
      throw HuggingFaceError.uvMissing
    }
    let script = try installScript()
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = uv
    process.arguments = ["run", "--quiet", "--no-project", "--script", script.path] + arguments
    process.currentDirectoryURL = cacheDirectory
    var environment = ProcessInfo.processInfo.environment
    environment["HF_HUB_CACHE"] = cacheDirectory.path
    environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
    // The Hub client otherwise keeps large files in a cache-wide store that outlives a model's folder; with this, deleting the folder frees everything the model downloaded.
    environment["HF_HUB_DISABLE_SHARED_BLOBS"] = "1"
    environment["HF_HUB_OFFLINE"] = allowsModelDownload ? nil : "1"
    process.environment = environment
    return try HuggingFaceProcess(process)
  }

  /// Releases every helper, including a download, before the application exits.
  static func stopAll() {
    HuggingFaceProcess.stopAll()
  }

  /// Copies the bundled script and its lockfile to their running location whenever they differ, so an updated app updates the helper.
  private static func installScript() throws -> URL {
    try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
    for name in ["asr.py", "asr.py.lock"] {
      guard let bundled = Bundle.vhraseResources.url(forResource: name, withExtension: nil)
      else {
        throw HuggingFaceError.failed("Vhrase's Hugging Face helper script is missing.")
      }
      let contents = try Data(contentsOf: bundled)
      let installed = scriptDirectory.appendingPathComponent(name)
      if (try? Data(contentsOf: installed)) != contents {
        try contents.write(to: installed, options: .atomic)
      }
    }
    return scriptDirectory.appendingPathComponent("asr.py")
  }

  /// An app launched from Finder inherits no shell path, so uv is looked up where its installers put it.
  private static func uvURL() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return [
      "/opt/homebrew/bin/uv",
      "/usr/local/bin/uv",
      "\(home)/.local/bin/uv",
      "\(home)/.cargo/bin/uv",
    ]
    .map(URL.init(fileURLWithPath:))
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
}

enum HuggingFaceError: LocalizedError {
  case uvMissing
  case notDownloaded(String)
  case stopped(String?)
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .uvMissing:
      "Hugging Face models need uv to build their Python runtime. Install it with “brew install uv”, then try again."
    case .notDownloaded(let model):
      "The Hugging Face model “\(model)” is not downloaded. Download it in Transcription before recording."
    case .stopped(let detail):
      "The Hugging Face runtime stopped\(detail.map { ": \($0)" } ?? ".")"
    case .failed(let message):
      message
    }
  }
}
