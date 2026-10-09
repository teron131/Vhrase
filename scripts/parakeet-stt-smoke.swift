// Exercises Vhrase's on-device Parakeet path on WAV recordings: recognition, finalization into history, silence, and cancellation.

import AVFoundation
import Foundation

@main
struct ParakeetSTTSmoke {
  @MainActor
  static func main() async throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let allowsDownload = arguments.first == "--download"
    if allowsDownload { arguments.removeFirst() }
    guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else {
      print(
        "Usage: parakeet-stt-smoke [--download] recording.wav \"expected phrase\" [recording.wav \"expected phrase\" ...]"
      )
      return
    }
    let samples = stride(from: 0, to: arguments.count, by: 2).map {
      (audio: URL(fileURLWithPath: arguments[$0]), expected: arguments[$0 + 1])
    }

    let store = ParakeetModelStore()
    if !store.isInstalled {
      guard allowsDownload else {
        throw SmokeFailure("The Parakeet model is not downloaded; rerun with --download.")
      }
      try await download(store)
    }
    let recognizer = store.recognizer
    var settings = DictationSettings.defaults
    settings.provider = .parakeet
    settings.adjustWithLLM = false

    // The same recognition, finalization, and history calls AppState makes after a recording stops.
    let suite = "Vhrase.ParakeetSmoke"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let historyStore = TranscriptHistoryStore(defaults: defaults)
    var history: [TranscriptHistoryItem] = []
    for sample in samples {
      let started = ContinuousClock.now
      let result = try await recognizer.transcribe(fileURL: sample.audio, settings: settings)
      let seconds = started.duration(to: .now) / .seconds(1)
      guard normalized(result.text).contains(normalized(sample.expected)) else {
        throw SmokeFailure(
          "\(sample.audio.lastPathComponent) lacks “\(sample.expected)”: \(result.text)")
      }
      let finalized = try await TranscriptFinalizer(settings: settings, llmAPIKey: "")
        .finalize(result, adjustment: .provider, targetApp: nil)
      history = historyStore.prepend(
        TranscriptHistoryItem(
          id: UUID(),
          createdAt: Date(),
          text: finalized.text,
          provider: result.providerName,
          transcriptionMode: settings.transcriptionModeTitle,
          cleanup: finalized.cleanup,
          targetAppName: nil,
          targetAppBundleIdentifier: nil,
          transcriptionSeconds: seconds
        ),
        to: history
      )
      print(
        "\(sample.audio.lastPathComponent) (\(String(format: "%.2f", seconds))s): \(finalized.text)"
      )
    }
    let saved = historyStore.load()
    guard saved.count == samples.count,
      saved.allSatisfy({
        $0.provider == "Parakeet" && $0.transcriptionMode == "After stop" && $0.cleanup == .raw
      })
    else {
      throw SmokeFailure("History did not retain the Parakeet transcripts and their metadata.")
    }
    print("history ok: \(saved.count) Parakeet entries, mode After stop, cleanup Raw")

    let workDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("parakeet-stt-smoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDirectory) }

    let silence = workDirectory.appendingPathComponent("silence.wav")
    try writeRecording([Float](repeating: 0, count: 48_000), to: silence)
    let silent = try await recognizer.transcribe(fileURL: silence, settings: settings)
    do {
      _ = try await TranscriptFinalizer(settings: settings, llmAPIKey: "")
        .finalize(silent, adjustment: .provider, targetApp: nil)
      throw SmokeFailure("Three seconds of silence produced text: \(silent.text)")
    } catch let error as NSError where error.domain == "Vhrase.Transcript" {
      print("silence ok: no transcript, so nothing would be delivered")
    }

    // Repeating a fixture gives FluidAudio several chunk boundaries at which cancellation can land.
    let long = workDirectory.appendingPathComponent("long.wav")
    let repeated = try readRecording(samples[0].audio)
    try writeRecording(
      Array(repeating: repeated, count: max(1, 240 * 16_000 / repeated.count)).flatMap { $0 },
      to: long)
    let cancelled = Task { try await recognizer.transcribe(fileURL: long, settings: settings) }
    try await Task.sleep(for: .milliseconds(250))
    let cancelledAt = ContinuousClock.now
    cancelled.cancel()
    do {
      let late = try await cancelled.value
      throw SmokeFailure("A cancelled transcription still returned \(late.text.count) characters.")
    } catch is CancellationError {
      let seconds = cancelledAt.duration(to: .now) / .seconds(1)
      print(
        "cancellation ok: stopped \(String(format: "%.2f", seconds))s after cancel without text")
    }
    let afterCancel = try await recognizer.transcribe(fileURL: samples[0].audio, settings: settings)
    guard normalized(afterCancel.text).contains(normalized(samples[0].expected)) else {
      throw SmokeFailure("Recognition failed after a cancelled run: \(afterCancel.text)")
    }
    print("recovery ok: the next transcription after cancellation succeeded")
  }

  @MainActor
  private static func download(_ store: ParakeetModelStore) async throws {
    store.download()
    var lastReport = ""
    while store.isDownloading {
      if case .downloading(let fraction, let isPreparing) = store.state {
        let report = isPreparing ? "preparing" : "\(Int(fraction * 10) * 10)%"
        if report != lastReport {
          print("download \(report)")
          lastReport = report
        }
      }
      try await Task.sleep(for: .milliseconds(500))
    }
    if case .failed(let message) = store.state {
      throw SmokeFailure("Download failed: \(message)")
    }
    print("download complete")
  }

  private static func normalized(_ text: String) -> String {
    text.lowercased().unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
      .map(String.init).joined()
      .split(separator: " ").joined(separator: " ")
  }

  private static func readRecording(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(
      pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(
      UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
  }

  /// Writes Vhrase's recording format: 16 kHz mono Int16 PCM WAV.
  private static func writeRecording(_ samples: [Float], to url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let file = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
      ])
    let buffer = AVAudioPCMBuffer(
      pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer {
      buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
    }
    try file.write(from: buffer)
  }
}

private struct SmokeFailure: LocalizedError {
  let errorDescription: String?

  init(_ message: String) {
    errorDescription = message
  }
}
