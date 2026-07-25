// Installs Vhrase's optional OpenCC dependency through an existing Homebrew installation.

import Foundation

struct OpenCCInstaller: Sendable {
  private let homebrewURL: URL?

  init(homebrewURL: URL? = Self.defaultHomebrewURL()) {
    self.homebrewURL = homebrewURL
  }

  static var isHomebrewAvailable: Bool {
    defaultHomebrewURL() != nil
  }

  /// Runs Homebrew away from the UI actor and preserves its failure output for the setup screen.
  func install() async throws {
    guard let homebrewURL else {
      throw OpenCCInstallerError.homebrewUnavailable
    }

    try await Task.detached(priority: .userInitiated) {
      try Self.runHomebrew(at: homebrewURL)
    }.value
  }

  private static func runHomebrew(at homebrewURL: URL) throws {
    let process = Process()
    process.executableURL = homebrewURL
    process.arguments = ["install", "opencc"]

    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    let outputCollector = OpenCCInstallOutputCollector()
    let reader = DispatchGroup()
    reader.enter()
    DispatchQueue.global(qos: .utility).async {
      defer {
        reader.leave()
      }
      outputCollector.store(
        output.fileHandleForReading.readDataToEndOfFile()
      )
    }

    do {
      try process.run()
    } catch {
      output.fileHandleForWriting.closeFile()
      reader.wait()
      throw error
    }
    process.waitUntilExit()
    reader.wait()

    guard process.terminationStatus == 0 else {
      let message = String(data: outputCollector.data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let conciseMessage = message.map { String($0.suffix(1_200)) }
      let failureMessage =
        conciseMessage.flatMap { $0.isEmpty ? nil : $0 }
        ?? "Homebrew exited with status \(process.terminationStatus)."
      throw OpenCCInstallerError.installFailed(
        failureMessage
      )
    }
  }

  private static func defaultHomebrewURL() -> URL? {
    [
      "/opt/homebrew/bin/brew",
      "/usr/local/bin/brew",
    ]
    .map(URL.init(fileURLWithPath:))
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
}

private enum OpenCCInstallerError: LocalizedError {
  case homebrewUnavailable
  case installFailed(String)

  var errorDescription: String? {
    switch self {
    case .homebrewUnavailable:
      "Homebrew is required to install OpenCC."
    case .installFailed(let message):
      "OpenCC installation failed: \(message)"
    }
  }
}

/// Stores Homebrew output behind a lock while its process drains the shared pipe.
private final class OpenCCInstallOutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var storedData = Data()

  var data: Data {
    lock.withLock { storedData }
  }

  func store(_ data: Data) {
    lock.withLock {
      storedData = data
    }
  }
}
