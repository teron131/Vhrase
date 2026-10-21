// Ensures one Vhrase process owns global shortcuts even when multiple app bundle copies are launched.

import AppKit
import Darwin
import Foundation

@MainActor
final class SingleInstanceGuard {
  /// Also true when the lock file cannot be opened, since a process that does not own the instance quits.
  let ownsInstance: Bool

  private var lockFileDescriptor: Int32 = -1

  init() {
    guard let lockURL = Self.lockURL() else {
      ownsInstance = true
      return
    }

    let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      ownsInstance = true
      return
    }

    if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
      lockFileDescriptor = descriptor
      ownsInstance = true
    } else {
      Darwin.close(descriptor)
      ownsInstance = false
    }
  }

  deinit {
    guard lockFileDescriptor >= 0 else {
      return
    }
    flock(lockFileDescriptor, LOCK_UN)
    Darwin.close(lockFileDescriptor)
  }

  /// Returns focus to the process holding the lock, then closes this duplicate before it can handle shortcuts.
  func handOffDuplicateLaunch() {
    guard !ownsInstance else {
      return
    }

    let currentProcess = ProcessInfo.processInfo.processIdentifier
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first { $0.processIdentifier != currentProcess }?
        .activate(options: [.activateAllWindows])
    }
    NSApplication.shared.terminate(nil)
  }

  private static func lockURL() -> URL? {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      return nil
    }
    let directory = applicationSupport.appendingPathComponent("Vhrase", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      return directory.appendingPathComponent("instance.lock", isDirectory: false)
    } catch {
      return nil
    }
  }
}
