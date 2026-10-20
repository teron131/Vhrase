// Describes a Hugging Face model's files to the setup store: the helper downloads them into Vhrase's own Hub cache, and a completion marker separates a finished download from an interrupted one.

import Foundation

struct HuggingFaceModel: OnDeviceModel {
  let title = STTProvider.huggingFace.title
  let id: String
  private let huggingFace: HuggingFaceRecognizer

  init(id: String, recognizer: HuggingFaceRecognizer) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    huggingFace = recognizer
  }

  /// The built-in turbo model's weights, measured on Hugging Face on 2026-10-13; other models are not measured.
  var downloadSizeLabel: String? {
    id == HuggingFaceModelReference.whisperTurbo ? "1.6 GB" : nil
  }

  /// Covers the built-in model plus the Python environment uv builds on the first download.
  var requiredFreeBytes: Int64? {
    id == HuggingFaceModelReference.whisperTurbo ? 4_000_000_000 : nil
  }

  let loadingNote = "Starting the Python runtime and loading the model takes several seconds."

  var recognizer: any SpeechToTextClient {
    huggingFace
  }

  var isInstalled: Bool {
    Self.isInstalled(id)
  }

  /// Reads only Vhrase's cache folder, so readiness never starts Python.
  static func isInstalled(_ id: String) -> Bool {
    guard let reference = try? HuggingFaceModelReference(id) else { return false }
    let marker = OnDeviceModelFiles.completionMarker(
      in: HuggingFaceRuntime.modelDirectory(for: reference))
    return FileManager.default.fileExists(atPath: marker.path)
  }

  /// The first download also builds the Python environment; the helper proves the model runs by transcribing a second of silence.
  func download(
    progress: @escaping @Sendable (_ fraction: Double, _ isIndeterminate: Bool) -> Void
  ) async throws {
    let reference = try HuggingFaceModelReference(id)
    let directory = HuggingFaceRuntime.modelDirectory(for: reference)
    var activeHelper: HuggingFaceProcess?
    do {
      // uv builds the environment before the helper can report anything, so setup starts without a percentage.
      progress(0, true)
      let helper = try HuggingFaceRuntime.start(
        ["download", reference.id], allowsModelDownload: true)
      activeHelper = helper
      var outcome: DownloadEvent?
      try await withTaskCancellationHandler {
        for try await line in helper.output.bytes.lines {
          let event = try JSONDecoder().decode(DownloadEvent.self, from: Data(line.utf8))
          switch event.event {
          case "progress": progress(event.fraction ?? 0, false)
          case "preparing": progress(1, true)
          default: outcome = event
          }
        }
        await helper.waitForExit()
      } onCancel: {
        helper.stop()
      }
      try Task.checkCancellation()
      guard outcome?.event == "installed" else {
        throw outcome?.message.map(HuggingFaceError.failed)
          ?? HuggingFaceError.stopped(helper.lastErrorLine)
      }
      try Data().write(to: OnDeviceModelFiles.completionMarker(in: directory))
    } catch {
      activeHelper?.stop()
      await activeHelper?.waitForExit()
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  func load() async throws {
    try await huggingFace.load(model: id)
  }

  /// Deletes the model's files; the Python environment stays in uv's cache, where other models reuse it.
  func remove() async throws {
    await huggingFace.unload()
    guard let reference = try? HuggingFaceModelReference(id) else { return }
    let directory = HuggingFaceRuntime.modelDirectory(for: reference)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
}

/// One line of the helper's download report: progress, the switch to loading, and how it ended.
private struct DownloadEvent: Decodable {
  let event: String
  let fraction: Double?
  let message: String?
}
