// Verifies shortcut and insertion permissions plus recording readiness for the selected polishing path.

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
    precondition(missingAccessibility.insertionPermissionActionTitle == "Allow Accessibility")
    let requestedAccessibility = presentation(
      accessibilityReady: false,
      accessibilityRequestedBefore: true
    )
    precondition(requestedAccessibility.insertionPermissionActionTitle == "Open Accessibility")
    precondition(presentation().insertionPermissionActionTitle == nil)

    var settings = DictationSettings.defaults
    settings.adjustmentModel = "test-model"
    settings.restyleChoice = .custom
    precondition(presentation().polishingSummary == "Raw transcripts")
    settings.customRestyleName = "Concise"
    for mode in DictationPolishing.allCases {
      settings.afterTranscription = mode
      let state = presentation(settings: settings)
      let shouldBlock = mode == .restyle
      precondition(state.coreRecordingReady != shouldBlock)
      precondition((state.transcriptionConfigurationIssue != nil) == shouldBlock)
      precondition((state.restyleIssue != nil) == shouldBlock)
      precondition(!state.transcriptionNeedsAttention)
      let expectedSummary =
        switch mode {
        case .off: "Raw transcripts"
        case .refine: "Refine · Minimal"
        case .restyle: "Restyle · Concise"
        }
      precondition(state.polishingSummary == expectedSummary)
      if shouldBlock { precondition(state.transcriptionConfigurationIssue == state.restyleIssue) }
    }
    settings.inputGainDB = 100
    precondition(presentation(settings: settings).transcriptionNeedsAttention)
    settings.inputGainDB = 0
    settings.customRestyleInstruction = "Keep the message concise."
    precondition(presentation(settings: settings).coreRecordingReady)
    precondition(presentation(settings: settings).restyleIssue == nil)
    settings.keyterms = String(repeating: "A", count: 51)
    let vocabulary = presentation(settings: settings)
    precondition(vocabulary.transcriptionConfigurationIssue == vocabulary.vocabularyIssue)
    precondition(!vocabulary.transcriptionNeedsAttention)
    settings.afterTranscription = .refine
    settings.polishPreferences.moneyStyle = .symbols
    precondition(presentation(settings: settings).polishingSummary == "Refine · Custom")
    print("readiness summary ok")
  }

  private static func presentation(
    settings customSettings: DictationSettings = .defaults,
    inputMonitoringReady: Bool = true,
    hotkeyPreset: HotkeyPreset = .controlOptionSpace,
    accessibilityReady: Bool = true,
    accessibilityRequestedBefore: Bool = false
  ) -> DictationPresentation {
    var settings = customSettings
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
      liveTranscript: ""
    )
  }
}
