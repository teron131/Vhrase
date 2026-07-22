// Composes Vhrase's main window, menu-bar control, settings scene, and focus-preserving recorder HUD.

import AppKit
import SwiftUI

@main
@MainActor
struct VhraseApp: App {
    @StateObject private var appState: AppState
    @AppStorage("app.hasCompletedFirstLaunch") private var hasCompletedFirstLaunch = false
    @State private var didHandleInitialMainWindow = false
    private let recorderHUD: RecorderHUDPanelController

    init() {
        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)
        recorderHUD = RecorderHUDPanelController(appState: appState)
    }

    var body: some Scene {
        Window("Vhrase", id: "main") {
            MainWindowView(appState: appState)
                .onAppear {
                    handleMainWindowAppearance()
                }
        }
        .defaultSize(width: 900, height: 680)

        MenuBarExtra("Vhrase", systemImage: appState.isRecording ? "mic.fill" : "mic") {
            MenuPopoverView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }

    /// Presents setup on first launch, then keeps later launches resident in the menu bar.
    private func handleMainWindowAppearance() {
        appState.refreshPermissions()

        guard !didHandleInitialMainWindow else {
            activateMainWindow()
            return
        }
        didHandleInitialMainWindow = true

        if hasCompletedFirstLaunch {
            suppressInitialMainWindow()
        } else {
            hasCompletedFirstLaunch = true
            activateMainWindow()
        }
    }

    /// Hides the automatically created scene without terminating the menu-bar utility.
    private func suppressInitialMainWindow() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            application.windows.first { window in
                window.canBecomeMain && !(window is NSPanel)
            }?.orderOut(nil)
        }
    }

    /// Brings the explicitly requested main window onto the primary desktop.
    private func activateMainWindow() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            guard let window = application.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
                application.activate()
                return
            }

            if let primaryScreen = NSScreen.screens.first,
               window.screen != primaryScreen {
                let visibleFrame = primaryScreen.visibleFrame
                let origin = NSPoint(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2
                )
                window.setFrameOrigin(origin)
            }

            application.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                application.activate()
                window.makeMain()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
