// Verifies feature-aware readiness across credentials and macOS permissions.

import Foundation

@main
struct ReadinessSummaryCheck {
  static func main() {
    precondition(
      presentation(
        keyReady: true,
        microphoneReady: true,
        screenReady: true,
        includeScreenshot: true
      ).selectedWorkflowReady
    )
    let missingInputMonitoring = presentation(
      keyReady: true,
      microphoneReady: true,
      screenReady: true,
      includeScreenshot: false,
      inputMonitoringReady: false,
      hotkeyPreset: .fn,
      accessibilityReady: false
    )
    precondition(!missingInputMonitoring.selectedShortcutReady)
    precondition(missingInputMonitoring.displayStatusTitle == "Shortcut setup")
    precondition(
      presentation(
        keyReady: true,
        microphoneReady: true,
        screenReady: true,
        includeScreenshot: false,
        inputMonitoringReady: false,
        hotkeyPreset: .fn,
        accessibilityReady: true
      ).selectedShortcutReady
    )
    let missingAccessibility = presentation(
      keyReady: true,
      microphoneReady: true,
      screenReady: true,
      includeScreenshot: false,
      accessibilityReady: false
    )
    precondition(missingAccessibility.needsAccessibilityForInsertion)
    precondition(missingAccessibility.insertionPermissionActionTitle == "Enable Insertion")
    let requestedAccessibility = presentation(
      keyReady: true,
      microphoneReady: true,
      screenReady: true,
      includeScreenshot: false,
      accessibilityReady: false,
      accessibilityRequestedBefore: true
    )
    precondition(requestedAccessibility.insertionPermissionActionTitle == "Open Accessibility")
    precondition(
      presentation(
        keyReady: true,
        microphoneReady: true,
        screenReady: false,
        includeScreenshot: false
      ).selectedWorkflowReady
    )
    precondition(
      presentation(
        keyReady: true,
        microphoneReady: true,
        screenReady: false,
        includeScreenshot: true
      ).selectedWorkflowReady == false
    )
    precondition(
      presentation(
        keyReady: false,
        microphoneReady: true,
        screenReady: true,
        includeScreenshot: true
      ).selectedWorkflowReady == false
    )
    precondition(
      presentation(
        keyReady: true,
        microphoneReady: false,
        screenReady: true,
        includeScreenshot: false
      ).selectedWorkflowReady == false
    )
    precondition(
      presentation(
        keyReady: true,
        microphoneReady: true,
        screenReady: true,
        includeScreenshot: false,
        accessibilityReady: false
      ).selectedWorkflowReady == false
    )
    precondition(
      !presentation(
        keyReady: true,
        microphoneReady: true,
        screenReady: true,
        includeScreenshot: false,
        accessibilityReady: false
      ).selectedWorkflowReady
    )

    print("readiness summary ok")
  }

  private static func presentation(
    keyReady: Bool,
    microphoneReady: Bool,
    screenReady: Bool,
    includeScreenshot: Bool,
    inputMonitoringReady: Bool = true,
    hotkeyPreset: HotkeyPreset = .controlOptionSpace,
    accessibilityReady: Bool = true,
    accessibilityRequestedBefore: Bool = false
  ) -> DictationPresentation {
    var settings = DictationSettings.defaults
    settings.includeScreenshot = includeScreenshot
    settings.hotkeyPreset = hotkeyPreset
    return DictationPresentation(
      status: .idle,
      settings: settings,
      xaiAPIKey: keyReady ? "xai-key" : "",
      elevenLabsAPIKey: "",
      permissions: [
        PermissionSnapshot(
          permission: .microphone,
          state: microphoneReady ? .granted : .notDetermined
        ),
        PermissionSnapshot(
          permission: .inputMonitoring,
          state: inputMonitoringReady ? .granted : .notDetermined
        ),
        PermissionSnapshot(
          permission: .screenRecording,
          state: screenReady ? .granted : .notDetermined
        ),
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
