// Owns process-wide launch and termination resources independently of any visible window or menu.

import AppKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
  let appState: AppState
  let mainWindow = MainWindowCoordinator()
  private let singleInstanceGuard: SingleInstanceGuard
  private let recorderHUD: RecorderHUDPanelController

  override init() {
    let instance = SingleInstanceGuard()
    singleInstanceGuard = instance
    appState = AppState(ownsInstance: instance.ownsInstance)
    recorderHUD = RecorderHUDPanelController(appState: appState)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    AppearancePreference.saved.apply()
    if singleInstanceGuard.ownsInstance {
      appState.credentials.loadSavedAfterLaunch()
    } else {
      singleInstanceGuard.handOffDuplicateLaunch()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    appState.prepareForTermination()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
