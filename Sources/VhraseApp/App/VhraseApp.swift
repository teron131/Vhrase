// Composes Vhrase's main window, menu-bar control, commands, and focus-preserving recorder HUD.

import AppKit
import SwiftUI

@main
@MainActor
struct VhraseApp: App {
  @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle

  var body: some Scene {
    Window("Vhrase", id: "main") {
      MainWindowView(appState: lifecycle.appState)
        .background(MainWindowAttachment(coordinator: lifecycle.mainWindow))
    }
    .defaultSize(width: 1120, height: 760)
    .commands {
      CommandGroup(replacing: .appSettings) {
        OpenVhraseSystemCommand()
          .environmentObject(lifecycle.mainWindow)
      }
    }

    MenuBarExtra {
      MenuPopoverView(appState: lifecycle.appState)
        .environmentObject(lifecycle.mainWindow)
    } label: {
      Image(nsImage: ParrotMark.menuBarImage)
        .renderingMode(.template)
        .accessibilityLabel("Vhrase")
    }
    .menuBarExtraStyle(.window)
  }
}

/// Restores the conventional Command-comma route into the unified System destination.
private struct OpenVhraseSystemCommand: View {
  @Environment(\.openWindow) private var openWindow
  @EnvironmentObject private var mainWindow: MainWindowCoordinator

  var body: some View {
    Button("Vhrase Settings…") {
      mainWindow.open(.system, using: openWindow)
    }
    .keyboardShortcut(",", modifiers: .command)
  }
}
