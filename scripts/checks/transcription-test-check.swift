// Exercises the production setup-test lifecycle with inert capture and recognition stand-ins, never opening a microphone or contacting a provider.

import Foundation

enum TranscriptionMode { case upload, realtime }
struct DictationSettings: Sendable { var transcriptionMode = TranscriptionMode.upload }
struct TranscriptionResult: Sendable { let text: String }
protocol SpeechToTextClient: Sendable {
  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult
}
struct AudioChunk: Sendable {
  let data: Data
  let level: Double
}

@MainActor
final class AudioRecorder {
  static var delayedStartup = false
  static var startup: CheckedContinuation<Void, Never>?
  static var lastURL: URL?
  static var cancellations = 0

  func start(
    settings: DictationSettings,
    onAudioChunk: @escaping @Sendable (AudioChunk) -> Void,
    onFailure: @escaping @MainActor (Error) -> Void
  ) async throws {
    if Self.delayedStartup {
      await withCheckedContinuation { Self.startup = $0 }
    }
    onAudioChunk(AudioChunk(data: Data([1]), level: 0.5))
    onAudioChunk(AudioChunk(data: Data([2]), level: 0.5))
  }

  func stop() async throws -> URL {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".cache/checks", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url =
      directory
      .appendingPathComponent("transcription-test-\(UUID().uuidString).wav")
    try Data([1, 2]).write(to: url)
    Self.lastURL = url
    return url
  }

  func cancel() { Self.cancellations += 1 }
}

final class RealtimeTranscriptionSession: @unchecked Sendable {
  @MainActor static var starts = 0
  @MainActor
  static func start(
    settings: DictationSettings, apiKey: String,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) throws -> RealtimeTranscriptionSession {
    starts += 1
    return RealtimeTranscriptionSession()
  }
  func sendAudioChunk(_ data: Data) {}
  func finish() async throws -> TranscriptionResult { TranscriptionResult(text: "realtime phrase") }
  func cancel() {}
}

actor Client: SpeechToTextClient {
  private let isDelayed: Bool
  private var continuation: CheckedContinuation<TranscriptionResult, Never>?
  private(set) var calls = 0

  init(isDelayed: Bool = false) { self.isDelayed = isDelayed }

  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    calls += 1
    if isDelayed {
      return await withCheckedContinuation { continuation = $0 }
    }
    return TranscriptionResult(text: "a short phrase")
  }

  func complete() { continuation?.resume(returning: TranscriptionResult(text: "late result")) }
  var isWaiting: Bool { continuation != nil }
}

@main
struct TranscriptionTestCheck {
  @MainActor
  static func main() async throws {
    // Successful capture must return raw text and delete its temporary WAV.
    let test = TranscriptionTest()
    let client = Client()
    test.start(settings: DictationSettings(), apiKey: "", client: client)
    await settle { test.state == .recording(secondsRemaining: 5) }
    test.stopAndTranscribe()
    await settle { test.state == .completed("a short phrase") }
    precondition(!FileManager.default.fileExists(atPath: AudioRecorder.lastURL!.path))
    let uploadCalls = await client.calls
    precondition(uploadCalls == 1)

    // Providers that ignore cancellation must not publish their late result; cancellation deletes the WAV immediately.
    let delayed = Client(isDelayed: true)
    test.start(settings: DictationSettings(), apiKey: "", client: delayed)
    await settle { test.state == .recording(secondsRemaining: 5) }
    test.stopAndTranscribe()
    for _ in 0..<1000 {
      if await delayed.isWaiting { break }
      await Task.yield()
    }
    let isWaiting = await delayed.isWaiting
    precondition(isWaiting)
    test.cancel()
    precondition(test.state == .idle)
    precondition(!FileManager.default.fileExists(atPath: AudioRecorder.lastURL!.path))
    await delayed.complete()
    for _ in 0..<100 { await Task.yield() }
    precondition(test.state == .idle)

    // Cancelling permission/startup invalidates its continuation before a new realtime test takes ownership.
    AudioRecorder.delayedStartup = true
    test.start(settings: DictationSettings(), apiKey: "", client: client)
    await settle { AudioRecorder.startup != nil }
    test.cancel()
    AudioRecorder.delayedStartup = false
    test.start(
      settings: DictationSettings(transcriptionMode: .realtime), apiKey: "", client: client)
    await settle { test.state == .recording(secondsRemaining: 5) }
    AudioRecorder.startup?.resume()
    AudioRecorder.startup = nil
    for _ in 0..<100 { await Task.yield() }
    precondition(test.state == .recording(secondsRemaining: 5))
    test.stopAndTranscribe()
    await settle { test.state == .completed("realtime phrase") }
    let finalUploadCalls = await client.calls
    precondition(finalUploadCalls == 1)
    precondition(!FileManager.default.fileExists(atPath: AudioRecorder.lastURL!.path))
    // Cancellation before the startup task runs must not open a paid realtime session.
    let starts = RealtimeTranscriptionSession.starts
    test.start(
      settings: DictationSettings(transcriptionMode: .realtime), apiKey: "", client: client)
    test.cancel()
    for _ in 0..<20 { await Task.yield() }
    precondition(RealtimeTranscriptionSession.starts == starts)

    // The automatic five-second stop follows the same recognition path as an explicit stop.
    test.start(settings: DictationSettings(), apiKey: "", client: client)
    let deadline = ContinuousClock.now + .seconds(7)
    while test.state != .completed("a short phrase"), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    precondition(test.state == .completed("a short phrase"))
    precondition(!FileManager.default.fileExists(atPath: AudioRecorder.lastURL!.path))
    print("Transcription setup test lifecycle checks passed")
  }

  @MainActor
  private static func settle(_ predicate: () -> Bool) async {
    for _ in 0..<1000 {
      if predicate() { return }
      await Task.yield()
    }
    preconditionFailure("Setup test did not reach its expected state")
  }
}
