// Owns a Hugging Face helper and its child processes, including pipe draining, bounded shutdown, and application termination cleanup.

import Darwin
import Foundation
import OSLog

/// Each Foundation Process has its own process group on macOS, so uv and the Python child share one shutdown boundary.
final class HuggingFaceProcess: @unchecked Sendable {
  private static let registry = OSAllocatedUnfairLock(initialState: Registry())
  private static let stopGrace = DispatchTimeInterval.seconds(1)

  let input: FileHandle
  let output: FileHandle
  private let errors: FileHandle
  private let process: Process
  private let completion = DispatchGroup()
  private let lock = NSLock()
  private var errorTail = Data()
  private var didRequestStop = false

  init(_ process: Process) throws {
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    self.process = process
    self.input = input.fileHandleForWriting
    self.output = output.fileHandleForReading
    self.errors = errors.fileHandleForReading
    // A closed helper must report a write error rather than send SIGPIPE to the app.
    _ = fcntl(self.input.fileDescriptor, F_SETNOSIGPIPE, 1)
    self.errors.readabilityHandler = { [weak self] handle in
      guard let data = try? handle.read(upToCount: 4_096), !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      guard let self else { return }
      self.lock.withLock {
        self.errorTail = Data((self.errorTail + data).suffix(4_096))
      }
    }
    let completion = completion
    completion.enter()
    process.terminationHandler = { child in
      let pid = child.processIdentifier
      // A wrapper can exit before its Python child; reap the entire owned group even on natural exit.
      Self.signalGroup(pid, signal: SIGKILL)
      Self.registry.withLock { $0.processes[pid] = nil }
      completion.leave()
    }
    do {
      try Self.registry.withLock { registry in
        guard !registry.isShuttingDown else { throw CancellationError() }
        try process.run()
        registry.processes[process.processIdentifier] = WeakProcess(self)
      }
    } catch {
      self.errors.readabilityHandler = nil
      completion.leave()
      throw error
    }
  }

  deinit {
    stop()
    errors.readabilityHandler = nil
    try? input.close()
    try? output.close()
    try? errors.close()
  }

  var processIdentifier: Int32 { process.processIdentifier }

  var isStopping: Bool { lock.withLock { didRequestStop } }

  /// The helper's final stderr line explains startup and inference failures without retaining unbounded library output.
  var lastErrorLine: String? {
    let text = lock.withLock { String(decoding: errorTail, as: UTF8.self) }
    return text.split(whereSeparator: \.isNewline).last.map(String.init)
  }

  /// Requests shutdown once, then kills a helper that has not exited within the grace period; neither step blocks the UI or cancellation handler.
  func stop() {
    let shouldStop = lock.withLock {
      guard !didRequestStop else { return false }
      didRequestStop = true
      return true
    }
    guard shouldStop else { return }
    try? input.close()
    guard completion.wait(timeout: .now()) == .timedOut else { return }
    let pid = process.processIdentifier
    Self.signalGroup(pid, signal: SIGTERM)
    let completion = completion
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.stopGrace) {
      guard completion.wait(timeout: .now()) == .timedOut else { return }
      Self.signalGroup(pid, signal: SIGKILL)
    }
  }

  /// Returns only after the process exits; async callers do not occupy an actor thread while uv and Python stop.
  func waitForExit() async {
    await withCheckedContinuation { continuation in
      completion.notify(queue: .global(qos: .utility)) { continuation.resume() }
    }
  }

  /// Stops all helpers before normal app exit and refuses launches from already queued tasks during termination.
  static func stopAll() {
    let processes = registry.withLock { registry in
      registry.isShuttingDown = true
      return registry.processes.values.compactMap(\.value)
    }
    for process in processes { process.stop() }
    let deadline = DispatchTime.now() + .seconds(3)
    for process in processes { _ = process.completion.wait(timeout: deadline) }
  }

  private static func signalGroup(_ pid: Int32, signal: Int32) {
    guard pid > 0 else { return }
    // Never signal the app's process group if a launch mechanism changes its grouping behavior.
    let group = getpgid(pid)
    if group == pid || group == -1 {
      _ = kill(-pid, signal)
    } else {
      _ = kill(pid, signal)
    }
  }

  private struct Registry: Sendable {
    var processes: [Int32: WeakProcess] = [:]
    var isShuttingDown = false
  }

  /// Access is serialized by the registry lock; a weak entry never keeps an otherwise unused helper alive.
  private final class WeakProcess: @unchecked Sendable {
    weak var value: HuggingFaceProcess?
    init(_ value: HuggingFaceProcess) { self.value = value }
  }
}
