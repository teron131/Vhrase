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
    precondition(readyDiagnostics.map(\.id) == [.ready])

    let missingInsertionAccess = diagnostics(
      settings: settings,
      accessibility: .notDetermined,
      inputMonitoring: .granted
    )
    precondition(missingInsertionAccess.map(\.id) == [.accessibilityPermission])

    var invalidSettings = settings
    invalidSettings.keyterms = String(repeating: "A", count: 51)
    let invalidConfiguration = diagnostics(
      settings: invalidSettings,
      accessibility: .granted,
      inputMonitoring: .granted
    )
    precondition(invalidConfiguration.first?.id == .transcriptionConfiguration)

    print("setup diagnostics ok")
  }

  private static func diagnostics(
    settings: DictationSettings,
    accessibility: PermissionState,
    inputMonitoring: PermissionState
  ) -> [SetupDiagnostic] {
    SetupDiagnostics(
      settings: settings,
      selectedProviderHasKey: true,
      hasLLMKey: true,
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
