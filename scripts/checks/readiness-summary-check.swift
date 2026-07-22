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
            ).readinessTitle == "Needs attention"
        )
        precondition(
            presentation(
                keyReady: false,
                microphoneReady: true,
                screenReady: true,
                includeScreenshot: true
            ).readinessTitle == "Needs attention"
        )
        precondition(
            presentation(
                keyReady: true,
                microphoneReady: false,
                screenReady: true,
                includeScreenshot: false
            ).readinessTitle == "Needs attention"
        )
        precondition(
            presentation(
                keyReady: true,
                microphoneReady: true,
                screenReady: true,
                includeScreenshot: false,
                accessibilityReady: false,
                pasteAfterTranscription: true
            ).readinessTitle == "Needs attention"
        )
        precondition(
            presentation(
                keyReady: true,
                microphoneReady: true,
                screenReady: true,
                includeScreenshot: false,
                accessibilityReady: false,
                pasteAfterTranscription: false
            ).selectedWorkflowReady
        )

        print("readiness summary ok")
    }

    private static func presentation(
        keyReady: Bool,
        microphoneReady: Bool,
        screenReady: Bool,
        includeScreenshot: Bool,
        accessibilityReady: Bool = true,
        pasteAfterTranscription: Bool = true
    ) -> DictationPresentation {
        var settings = DictationSettings.defaults
        settings.includeScreenshot = includeScreenshot
        settings.pasteAfterTranscription = pasteAfterTranscription
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
                    permission: .screenRecording,
                    state: screenReady ? .granted : .notDetermined
                ),
                PermissionSnapshot(
                    permission: .accessibility,
                    state: accessibilityReady ? .granted : .notDetermined
                ),
            ],
            liveTranscript: "",
            recordingElapsedSeconds: 0
        )
    }
}
