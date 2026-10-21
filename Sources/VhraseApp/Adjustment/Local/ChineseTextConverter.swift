// Normalizes final transcript text to Hong Kong Traditional Chinese through OpenCC when available.

import Darwin
import Foundation

struct ChineseTextConverter: Sendable {
  private let executableURL: URL?
  private let configName: String
  private let timeoutSeconds: TimeInterval

  init(
    executableURL: URL? = Self.defaultExecutableURL(),
    configName: String = "s2hk.json",
    timeoutSeconds: TimeInterval = 10
  ) {
    self.executableURL = executableURL
    self.configName = configName
    self.timeoutSeconds = timeoutSeconds
  }

  static var isAvailable: Bool {
    defaultExecutableURL() != nil
  }

  /// Blocks until OpenCC exits or `timeoutSeconds` pass. When OpenCC is missing or fails, the text comes back unchanged with a warning.
  func convert(_ text: String) -> (text: String, warning: String?) {
    guard let executableURL else {
      return (text, "OpenCC s2hk unavailable. Final transcript was not normalized.")
    }

    do {
      return (try runOpenCC(text, executableURL: executableURL), nil)
    } catch {
      return (text, "OpenCC s2hk failed: \(error.localizedDescription)")
    }
  }

  private func runOpenCC(
    _ text: String,
    executableURL: URL
  ) throws -> String {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["-c", configName]

    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    let termination = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      termination.signal()
    }

    try process.run()
    let outputCollector = ProcessOutputCollector()
    let readers = DispatchGroup()
    readers.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      defer {
        readers.leave()
      }
      outputCollector.storeOutput(
        output.fileHandleForReading.readDataToEndOfFile()
      )
    }
    readers.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      defer {
        readers.leave()
      }
      outputCollector.storeError(
        error.fileHandleForReading.readDataToEndOfFile()
      )
    }

    try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    try input.fileHandleForWriting.close()
    let timeout = DispatchTimeInterval.milliseconds(
      max(1, Int(timeoutSeconds * 1_000))
    )
    if termination.wait(timeout: .now() + timeout) == .timedOut {
      if process.isRunning {
        process.terminate()
      }
      if termination.wait(timeout: .now() + .seconds(1)) == .timedOut,
        process.isRunning
      {
        kill(process.processIdentifier, SIGKILL)
        _ = termination.wait(timeout: .now() + .seconds(1))
      }
      process.waitUntilExit()
      readers.wait()
      throw ChineseTextConverterError.timedOut(seconds: timeoutSeconds)
    }
    process.waitUntilExit()
    readers.wait()

    let converted =
      String(
        data: outputCollector.output,
        encoding: .utf8
      ) ?? ""
    if process.terminationStatus == 0 {
      return converted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let message = String(
      data: outputCollector.error,
      encoding: .utf8
    )?
    .trimmingCharacters(in: .whitespacesAndNewlines)
    let detail =
      message.flatMap { $0.isEmpty ? nil : $0 }
      ?? "OpenCC exited with status \(process.terminationStatus)."
    throw NSError(
      domain: "Vhrase.OpenCC",
      code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: detail]
    )
  }

  private static func defaultExecutableURL() -> URL? {
    [
      "/opt/homebrew/bin/opencc",
      "/usr/local/bin/opencc",
      "/usr/bin/opencc",
    ]
    .map(URL.init(fileURLWithPath:))
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
}

private enum ChineseTextConverterError: LocalizedError {
  case timedOut(seconds: TimeInterval)

  var errorDescription: String? {
    switch self {
    case .timedOut(let seconds):
      "OpenCC timed out after \(seconds.formatted(.number.precision(.fractionLength(1)))) seconds."
    }
  }
}

/// Stores concurrently drained process output behind a lock so OpenCC cannot block on full stdout or stderr pipes.
private final class ProcessOutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var storedOutput = Data()
  private var storedError = Data()

  var output: Data {
    lock.withLock { storedOutput }
  }

  var error: Data {
    lock.withLock { storedError }
  }

  func storeOutput(_ data: Data) {
    lock.withLock {
      storedOutput = data
    }
  }

  func storeError(_ data: Data) {
    lock.withLock {
      storedError = data
    }
  }
}
