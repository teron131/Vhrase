// Verifies record-button actions against provider credential or model, microphone, and workflow readiness.

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

    let missingModel = presentation(
      status: .idle, keyReady: true, provider: .parakeet, readiness: .missingLocalModel)
    precondition(!missingModel.coreRecordingReady)
    precondition(missingModel.recordAction == .openSetup)
    precondition(missingModel.recordButtonTitle == "Download Model")
    precondition(missingModel.recordButtonSystemImage == "arrow.down.circle.fill")
    precondition(missingModel.statusMessage == "Download the Parakeet model before recording.")
    let readyModel = presentation(status: .idle, keyReady: true, provider: .parakeet)
    precondition(readyModel.recordAction == .toggleRecording)
    precondition(readyModel.compactWorkflowSummary.hasPrefix("Parakeet after stop"))

    print("record button state ok")
  }

  private static func presentation(
    status: AppStatus,
    keyReady: Bool,
    keyterms: String = "",
    provider: STTProvider = .xai,
    readiness: ProviderReadiness? = nil
  ) -> DictationPresentation {
    var settings = DictationSettings.defaults
    settings.provider = provider
    settings.keyterms = keyterms
    return DictationPresentation(
      status: status,
      settings: settings,
      providerReadiness: readiness ?? (keyReady ? .ready : .missingAPIKey),
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
