// Proves warm-model eviction, memory-pressure handling, and helper process-group shutdown without model downloads, microphone capture, or system-wide memory stress.

import Darwin
import Foundation
import OSLog

@main
struct HuggingFaceProcessCheck {
  static func main() async throws {
    defer { HuggingFaceProcess.stopAll() }
    try await checkMemoryPressure()

    let graceful = try helper("read line; printf '%s\\n' \"$line\"; cat")
    let gracefulPID = graceful.processIdentifier
    precondition(getpgid(gracefulPID) == gracefulPID, "The helper must own its process group")
    try graceful.input.write(contentsOf: Data("ready\n".utf8))
    precondition(String(decoding: graceful.output.availableData, as: UTF8.self) == "ready\n")
    graceful.stop()
    await graceful.waitForExit()
    try await requireExit([gracefulPID])

    // Both the wrapper and child ignore TERM; the one-second KILL fallback must release them together.
    let stubborn = try helper(
      "trap '' TERM; /bin/sh -c 'trap \"\" TERM; exec /bin/sleep 30' & printf '%s\\n' \"$!\"; wait")
    let childPID = Int32(
      String(decoding: stubborn.output.availableData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines))!
    let wrapperPID = stubborn.processIdentifier
    precondition(getpgid(childPID) == wrapperPID)
    let started = ContinuousClock.now
    stubborn.stop()
    stubborn.stop()
    await stubborn.waitForExit()
    try await requireExit([wrapperPID, childPID])
    let seconds = started.duration(to: .now) / .seconds(1)
    precondition(seconds < 3, "A stubborn runtime must not stall cancellation")
    print(
      "stubborn helper and child exited in \(seconds.formatted(.number.precision(.fractionLength(2))))s"
    )

    // Normal wrapper exit must not strand a child that still holds model memory or inherited output pipes.
    let orphan = try helper("/bin/sleep 30 & printf '%s\\n' \"$!\"")
    let orphanPID = Int32(
      String(decoding: orphan.output.availableData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines))!
    await orphan.waitForExit()
    try await requireExit([orphan.processIdentifier, orphanPID])

    let first = try helper("exec /bin/sleep 30")
    let second = try helper("exec /bin/sleep 30")
    HuggingFaceProcess.stopAll()
    try await requireExit([first.processIdentifier, second.processIdentifier])
    do {
      _ = try helper("exec /bin/sleep 30")
      preconditionFailure("Termination must reject a queued helper launch")
    } catch is CancellationError {}
    print("hugging face process group lifecycle ok")
  }

  /// Drives the production recognizer and process owner through a controlled JSON-line helper, injecting pressure only into this recognizer.
  private static func checkMemoryPressure() async throws {
    try FileManager.default.createDirectory(
      at: HuggingFaceRuntime.directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: HuggingFaceRuntime.directory) }
    let recognizer = HuggingFaceRecognizer()
    precondition(HuggingFaceRecognizer.idleUnloadDelay == .seconds(600))
    try await recognizer.load(model: "test/model")
    let firstPID = HuggingFaceRuntime.pids.last!
    try await recognizer.load(model: "test/model")
    precondition(
      HuggingFaceRuntime.pids == [firstPID], "Normal memory pressure must permit warm reuse")

    await recognizer.handleMemoryPressure(isElevated: true)
    try await requireExit([firstPID])
    try await recognizer.load(model: "test/model")
    precondition(
      HuggingFaceRuntime.pids == [firstPID], "Elevated pressure must suppress speculative warm-up")

    let result = try await recognizer.transcribe(
      fileURL: HuggingFaceRuntime.directory.appendingPathComponent("immediate.wav"),
      settings: .defaults)
    precondition(
      result.text == "recognized text",
      "Explicit transcription must remain available under pressure")
    try await requireExit([HuggingFaceRuntime.pids.last!])
    let startsUnderPressure = HuggingFaceRuntime.pids.count

    await recognizer.handleMemoryPressure(isElevated: false)
    precondition(
      HuggingFaceRuntime.pids.count == startsUnderPressure,
      "Normal pressure must not automatically reload a model")
    try await recognizer.load(model: "test/model")
    let activePID = HuggingFaceRuntime.pids.last!
    let transcription = Task {
      try await recognizer.transcribe(
        fileURL: HuggingFaceRuntime.directory.appendingPathComponent("blocked.wav"),
        settings: .defaults)
    }
    let began = HuggingFaceRuntime.directory.appendingPathComponent("began")
    let deadline = ContinuousClock.now + .seconds(3)
    while !FileManager.default.fileExists(atPath: began.path) {
      precondition(ContinuousClock.now < deadline, "The controlled transcription did not start")
      try await Task.sleep(for: .milliseconds(10))
    }
    await recognizer.handleMemoryPressure(isElevated: true)
    precondition(kill(activePID, 0) == 0, "Memory pressure must not interrupt active transcription")
    try Data().write(to: HuggingFaceRuntime.directory.appendingPathComponent("release"))
    let finished = try await transcription.value
    precondition(finished.text == "recognized text")
    try await requireExit([activePID])
    await recognizer.unload()
    print("hugging face warm reuse, pressure eviction, and active-request protection ok")
  }

  private static func helper(_ command: String) throws -> HuggingFaceProcess {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    return try HuggingFaceProcess(process)
  }

  private static func requireExit(_ pids: [Int32]) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while pids.contains(where: { kill($0, 0) == 0 }) {
      guard ContinuousClock.now < deadline else {
        preconditionFailure("An owned helper process survived shutdown")
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

/// Replaces only external model setup; the recognizer's request queue, cancellation, timers, and subprocess ownership are production code.
enum HuggingFaceRuntime {
  static let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(".cache/checks/hugging-face-pressure-\(UUID().uuidString)")
  private static let launched = OSAllocatedUnfairLock(initialState: [Int32]())
  static var pids: [Int32] { launched.withLock { $0 } }

  static func start(_ arguments: [String], allowsModelDownload: Bool) throws -> HuggingFaceProcess {
    precondition(arguments == ["serve"] && !allowsModelDownload)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      "-c",
      #"""
      while IFS= read -r request; do
        case "$request" in
          *blocked.wav*)
            touch "$1/began"
            while [ ! -f "$1/release" ]; do sleep 0.02; done
            ;;
        esac
        printf '%s\n' '{"ok":true,"text":"recognized text","device":"test","precision":"test"}'
      done
      """#, "pressure-check", directory.path,
    ]
    let helper = try HuggingFaceProcess(process)
    launched.withLock { $0.append(helper.processIdentifier) }
    return helper
  }
}

enum HuggingFaceModel {
  static func isInstalled(_ model: String) -> Bool { true }
}

enum HuggingFaceError: Error {
  case notDownloaded(String)
  case failed(String)
  case stopped(String?)
}
