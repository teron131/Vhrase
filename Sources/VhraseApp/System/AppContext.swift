// Tracks and restores the external application targeted by a dictation workflow.

@preconcurrency import AppKit
import Foundation

@MainActor
final class AppContext {
  private static let activationSettleDelay: Duration = .milliseconds(150)
  private let ownBundleIdentifier = Bundle.main.bundleIdentifier
  private var lastTargetApp: FrontmostApp?

  init() {
    lastTargetApp = eligibleFrontmostApp()
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication,
        let bundleIdentifier = application.bundleIdentifier,
        !bundleIdentifier.isEmpty
      else {
        return
      }
      let name = application.localizedName ?? "Unknown"
      Task { @MainActor in
        self?.rememberActivatedApp(
          name: name,
          bundleIdentifier: bundleIdentifier
        )
      }
    }
  }

  /// Returns the current external app or the most recently activated one when Vhrase owns focus.
  func targetApp() -> FrontmostApp? {
    if let app = eligibleFrontmostApp() {
      lastTargetApp = app
    }
    return lastTargetApp
  }

  /// After a switch it waits briefly before returning, because frontmost status flips before the app's window becomes key and a shortcut sent in that gap is dropped.
  func activate(_ target: FrontmostApp) async -> Bool {
    guard !target.bundleIdentifier.isEmpty,
      let application =
        NSRunningApplication
        .runningApplications(withBundleIdentifier: target.bundleIdentifier)
        .first
    else {
      return false
    }

    let wasFrontmost =
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleIdentifier
    if !wasFrontmost {
      guard application.activate(options: [.activateAllWindows]) else {
        return false
      }
    }

    for _ in 0..<10 {
      if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleIdentifier {
        lastTargetApp = target
        if !wasFrontmost {
          try? await Task.sleep(for: Self.activationSettleDelay)
        }
        return true
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return false
  }

  private func rememberActivatedApp(
    name: String,
    bundleIdentifier: String
  ) {
    guard bundleIdentifier != ownBundleIdentifier else {
      return
    }
    lastTargetApp = FrontmostApp(
      name: name,
      bundleIdentifier: bundleIdentifier
    )
  }

  private func eligibleFrontmostApp() -> FrontmostApp? {
    guard let application = NSWorkspace.shared.frontmostApplication,
      let target = frontmostApp(application),
      target.bundleIdentifier != ownBundleIdentifier
    else {
      return nil
    }
    return target
  }

  private func frontmostApp(_ application: NSRunningApplication) -> FrontmostApp? {
    guard let bundleIdentifier = application.bundleIdentifier,
      !bundleIdentifier.isEmpty
    else {
      return nil
    }
    return FrontmostApp(
      name: application.localizedName ?? "Unknown",
      bundleIdentifier: bundleIdentifier
    )
  }
}
