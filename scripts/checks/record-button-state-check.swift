// Verifies record-button actions against provider, microphone, and workflow readiness.

import Foundation

@main
struct RecordButtonStateCheck {
  static func main() {
    precondition(presentation(status: .idle, keyReady: true).recordAction == .toggleRecording)
    precondition(presentation(status: .completed, keyReady: true).recordAction == .toggleRecording)
    precondition(
      presentation(status: .failed("x"), keyReady: true).recordAction == .toggleRecording)
    precondition(presentation(status: .idle, keyReady: false).recordAction == .openSetup)
    precondition(presentation(status: .completed, keyReady: false).recordAction == .openSetup)
    precondition(presentation(status: .failed("x"), keyReady: false).recordAction == .openSetup)
    precondition(presentation(status: .preparing, keyReady: true).recordAction == .cancelRecording)
    precondition(presentation(status: .recording, keyReady: false).recordAction == .toggleRecording)
    precondition(presentation(status: .transcribing, keyReady: true).recordAction == .disabled)
    precondition(presentation(status: .adjusting, keyReady: true).recordAction == .disabled)

    let invalidSettings = presentation(
      status: .idle,
      keyReady: true,
      keyterms: String(repeating: "A", count: 51)
    )
    precondition(!invalidSettings.coreRecordingReady)
    precondition(invalidSettings.displayStatusTitle == "Check settings")
    precondition(invalidSettings.recordAction == .openSetup)
    precondition(invalidSettings.recordButtonTitle == "Review Settings")
    precondition(invalidSettings.statusMessage?.contains("found 51") == true)

    print("record button state ok")
  }

  private static func presentation(
    status: AppStatus,
    keyReady: Bool,
    keyterms: String = ""
  ) -> DictationPresentation {
    var settings = DictationSettings.defaults
    settings.provider = .xai
    settings.keyterms = keyterms
    return DictationPresentation(
      status: status,
      settings: settings,
      selectedProviderHasKey: keyReady,
      permissions: [
        PermissionSnapshot(
          permission: .microphone,
          state: .granted
        )
      ],
      liveTranscript: "",
      recordingElapsedSeconds: 0
    )
  }
}
