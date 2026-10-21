// Owns getting OpenCC onto this Mac for Chinese output: the Homebrew install, its progress and failure, and the next step Refinement and System both offer while OpenCC is missing.

import AppKit
import Foundation

@MainActor
final class OpenCCSetup: ObservableObject {
  enum Installation: Equatable {
    case idle
    case installing
    case failed(String)
  }

  @Published private(set) var installation = Installation.idle
  /// Receives install progress and outcomes for the app's transient notice.
  var onNotice: (String) -> Void = { _ in }
  private let installer = OpenCCInstaller()

  /// Reads the disk on every call, so an install made outside Vhrase shows at the next redraw.
  var isInstalled: Bool {
    ChineseTextConverter.isAvailable
  }

  var canInstall: Bool {
    OpenCCInstaller.isHomebrewAvailable
  }

  var failureMessage: String? {
    guard case .failed(let message) = installation else { return nil }
    return message
  }

  /// Names the button that moves setup forward while OpenCC is missing and no install is running: an install where Homebrew exists, otherwise Homebrew's own page.
  var nextStepTitle: String {
    guard canInstall else { return "Get Homebrew" }
    return failureMessage == nil ? "Install OpenCC" : "Retry Install"
  }

  /// Opens Homebrew's page when Homebrew is missing; otherwise calls `confirmInstall`, which should ask before `install` runs Homebrew.
  func takeNextStep(confirmInstall: () -> Void) {
    if canInstall {
      confirmInstall()
    } else {
      openHomebrewSetup()
    }
  }

  func install() {
    guard installation != .installing else { return }
    installation = .installing
    onNotice("Installing OpenCC with Homebrew…")
    let installer = installer
    Task {
      do {
        try await installer.install()
        guard ChineseTextConverter.isAvailable else {
          throw NSError(
            domain: "Vhrase.OpenCCInstaller",
            code: 1,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Homebrew completed, but the OpenCC executable was not found."
            ]
          )
        }
        installation = .idle
        onNotice("OpenCC installed. New transcripts will use s2t conversion.")
      } catch {
        installation = .failed(error.localizedDescription)
        onNotice(error.localizedDescription)
      }
    }
  }

  func openHomebrewSetup() {
    NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
  }
}
