// Centralizes first-launch visibility and explicit window navigation for menu actions and Command-comma.

import AppKit
import SwiftUI

@MainActor
final class MainWindowCoordinator: ObservableObject {
  private weak var window: NSWindow?
  private var didHandleInitialWindow = false

  /// Changes destination before opening the scene, then focuses the same window even after it was hidden.
  func open(_ tab: MainWindowTab, using openWindow: OpenWindowAction) {
    UserDefaults.standard.set(tab.rawValue, forKey: "mainWindow.selectedTab")
    openWindow(id: "main")
    DispatchQueue.main.async { [weak self] in self?.activate() }
  }

  /// Attaches to the actual scene window rather than guessing from unrelated AppKit windows or panels.
  func attach(_ window: NSWindow) {
    guard self.window !== window else { return }
    self.window = window
    guard !didHandleInitialWindow else { return }
    didHandleInitialWindow = true
    let defaults = UserDefaults.standard
    let suppress =
      defaults.bool(forKey: "app.hasCompletedFirstLaunch")
      && !CommandLine.arguments.contains("--show-window")
    if !suppress { defaults.set(true, forKey: "app.hasCompletedFirstLaunch") }
    DispatchQueue.main.async { [weak self, weak window] in
      if suppress {
        window?.orderOut(nil)
      } else {
        self?.activate()
      }
    }
  }

  private func activate() {
    NSApplication.shared.setActivationPolicy(.accessory)
    guard let window else { return }
    if let primaryScreen = NSScreen.screens.first, window.screen != primaryScreen {
      let frame = primaryScreen.visibleFrame
      window.setFrameOrigin(
        NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
    }
    NSApplication.shared.activate()
    window.makeKeyAndOrderFront(nil)
  }
}

/// Reports the scene's window once AppKit attaches its content, including recreation after closing.
struct MainWindowAttachment: NSViewRepresentable {
  let coordinator: MainWindowCoordinator

  func makeNSView(context: Context) -> AttachmentView {
    AttachmentView(coordinator: coordinator)
  }

  func updateNSView(_ view: AttachmentView, context: Context) {}

  final class AttachmentView: NSView {
    let coordinator: MainWindowCoordinator

    init(coordinator: MainWindowCoordinator) {
      self.coordinator = coordinator
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window { coordinator.attach(window) }
    }
  }
}
