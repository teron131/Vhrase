// Verifies insertion access remains required without treating optional Fn monitoring as a blocker, and that local recognition asks for its model instead of a key.

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

    var localSettings = settings
    localSettings.provider = .parakeet
    let missingModel = diagnostics(
      settings: localSettings, accessibility: .granted, inputMonitoring: .granted,
      providerReadiness: .missingLocalModel)
    precondition(missingModel.map(\.id) == [.localModel])
    let readyModel = diagnostics(
      settings: localSettings, accessibility: .granted, inputMonitoring: .granted)
    precondition(readyModel.map(\.id) == [.ready])
    precondition(readyModel.first?.detail.contains("local model") == true)

    // Missing OpenCC is a setup step only while Chinese output is on.
    let missingOpenCC = diagnostics(
      settings: settings, accessibility: .granted, inputMonitoring: .granted,
      chineseConversionIsAvailable: false)
    precondition(missingOpenCC.map(\.id) == [.openCC])
    var withoutChineseOutput = settings
    withoutChineseOutput.convertChineseOutput = false
    let openCCNotNeeded = diagnostics(
      settings: withoutChineseOutput, accessibility: .granted, inputMonitoring: .granted,
      chineseConversionIsAvailable: false)
    precondition(openCCNotNeeded.map(\.id) == [.ready])

    print("setup diagnostics ok")
  }

  private static func diagnostics(
    settings: DictationSettings,
    accessibility: PermissionState,
    inputMonitoring: PermissionState,
    providerReadiness: ProviderReadiness = .ready,
    chineseConversionIsAvailable: Bool = true
  ) -> [SetupDiagnostic] {
    SetupDiagnostics(
      settings: settings,
      providerReadiness: providerReadiness,
      hasLLMKey: true,
      permissions: [
        PermissionSnapshot(permission: .microphone, state: .granted),
        PermissionSnapshot(permission: .inputMonitoring, state: inputMonitoring),
        PermissionSnapshot(permission: .screenRecording, state: .granted),
        PermissionSnapshot(permission: .accessibility, state: accessibility),
      ],
      chineseConversionIsAvailable: chineseConversionIsAvailable
    ).build()
  }
}
