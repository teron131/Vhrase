// Verifies insertion access remains required without treating optional Fn monitoring as a blocker.

import Foundation

@main
struct SetupDiagnosticsCheck {
    static func main() {
        var settings = DictationSettings.defaults
        settings.hotkeyPreset = .fn

        let readyDiagnostics = diagnostics(
            settings: settings,
            accessibility: .granted,
            inputMonitoring: .notDetermined
        )
        precondition(readyDiagnostics.map(\.id) == ["ready"])

        let missingInsertionAccess = diagnostics(
            settings: settings,
            accessibility: .notDetermined,
            inputMonitoring: .granted
        )
        precondition(missingInsertionAccess.contains { $0.id == "accessibility-permission" })
        precondition(!missingInsertionAccess.contains { $0.id == "input-monitoring-permission" })

        print("setup diagnostics ok")
    }

    private static func diagnostics(
        settings: DictationSettings,
        accessibility: PermissionState,
        inputMonitoring: PermissionState
    ) -> [SetupDiagnostic] {
        SetupDiagnostics(
            settings: settings,
            xaiAPIKey: "xai-key",
            elevenLabsAPIKey: "elevenlabs-key",
            llmAPIKey: "llm-key",
            permissions: [
                PermissionSnapshot(permission: .microphone, state: .granted),
                PermissionSnapshot(permission: .inputMonitoring, state: inputMonitoring),
                PermissionSnapshot(permission: .screenRecording, state: .granted),
                PermissionSnapshot(permission: .accessibility, state: accessibility),
            ],
            chineseConversionIsAvailable: true
        ).build()
    }
}
