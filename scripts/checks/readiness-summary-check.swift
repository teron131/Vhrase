// Verifies feature-aware shortcut and insertion readiness across macOS permissions.

import Foundation

@main
struct ReadinessSummaryCheck {
  static func main() {
    let missingInputMonitoring = presentation(
      inputMonitoringReady: false,
      hotkeyPreset: .fn,
      accessibilityReady: false
    )
    precondition(!missingInputMonitoring.selectedShortcutReady)
    precondition(missingInputMonitoring.displayStatusTitle == "Shortcut setup")
    precondition(
      presentation(
        inputMonitoringReady: false,
        hotkeyPreset: .fn,
        accessibilityReady: true
      ).selectedShortcutReady
    )
    let missingAccessibility = presentation(accessibilityReady: false)
    precondition(missingAccessibility.insertionPermissionActionTitle == "Enable Insertion")
    let requestedAccessibility = presentation(
      accessibilityReady: false,
      accessibilityRequestedBefore: true
    )
    precondition(requestedAccessibility.insertionPermissionActionTitle == "Open Accessibility")
    precondition(presentation().insertionPermissionActionTitle == nil)

    print("readiness summary ok")
  }

  private static func presentation(
    inputMonitoringReady: Bool = true,
    hotkeyPreset: HotkeyPreset = .controlOptionSpace,
    accessibilityReady: Bool = true,
    accessibilityRequestedBefore: Bool = false
  ) -> DictationPresentation {
    var settings = DictationSettings.defaults
    settings.hotkeyPreset = hotkeyPreset
    return DictationPresentation(
      status: .idle,
      settings: settings,
      providerReadiness: .ready,
      permissions: [
        PermissionSnapshot(permission: .microphone, state: .granted),
        PermissionSnapshot(
          permission: .inputMonitoring,
          state: inputMonitoringReady ? .granted : .notDetermined
        ),
        PermissionSnapshot(permission: .screenRecording, state: .granted),
        PermissionSnapshot(
          permission: .accessibility,
          state: accessibilityReady ? .granted : .notDetermined,
          requestedBefore: accessibilityRequestedBefore
        ),
      ],
      liveTranscript: "",
      recordingElapsedSeconds: 0
    )
  }
}
