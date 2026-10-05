// Derives actionable setup diagnostics from settings, credentials, and macOS permission state.

import Foundation

struct SetupDiagnostics {
  let settings: DictationSettings
  let selectedProviderHasKey: Bool
  let hasLLMKey: Bool
  let permissions: [PermissionSnapshot]
  let chineseConversionIsAvailable: Bool

  func build() -> [SetupDiagnostic] {
    var diagnostics: [SetupDiagnostic] = []

    if let issue = TranscriptionContract.configurationIssue(in: settings) {
      diagnostics.append(
        SetupDiagnostic(
          id: .transcriptionConfiguration,
          title: "Transcription settings",
          detail: issue,
          systemImage: "slider.horizontal.3"
        ))
    }
    if !selectedProviderHasKey {
      diagnostics.append(
        SetupDiagnostic(
          id: .providerKey,
          title: "\(settings.provider.title) key",
          detail: "Add the selected STT provider key in Settings.",
          systemImage: "key.fill"
        ))
    }
    if permissionState(for: .microphone)?.isReady != true {
      diagnostics.append(
        SetupDiagnostic(
          id: .microphonePermission,
          title: "Microphone",
          detail: "Grant mic access before real recording.",
          systemImage: "mic.fill"
        ))
    }
    let accessibilityIsReady = permissionState(for: .accessibility)?.isReady == true
    if !accessibilityIsReady {
      diagnostics.append(
        SetupDiagnostic(
          id: .accessibilityPermission,
          title: settings.hotkeyPreset == .fn ? "Shortcut and text insertion" : "Text insertion",
          detail: settings.hotkeyPreset == .fn
            ? "Grant Accessibility once so Fn/Globe works globally and transcripts return to the original app."
            : "Grant Accessibility so transcripts return to the original app.",
          systemImage: "cursorarrow.motionlines"
        ))
    }
    if settings.adjustWithLLM, !hasLLMKey {
      diagnostics.append(
        SetupDiagnostic(
          id: .adjustmentKey,
          title: "LLM adjustment",
          detail: "LLM API key is required for transcript cleanup.",
          systemImage: "wand.and.stars"
        ))
    }
    if settings.adjustWithLLM,
      settings.includeScreenshot,
      permissionState(for: .screenRecording)?.isReady != true
    {
      diagnostics.append(
        SetupDiagnostic(
          id: .screenPermission,
          title: "Screenshot context",
          detail: "Grant Screen Recording or turn screenshot off.",
          systemImage: "rectangle.on.rectangle"
        ))
    }
    if !chineseConversionIsAvailable {
      diagnostics.append(
        SetupDiagnostic(
          id: .openCC,
          title: "OpenCC s2hk",
          detail: "Install OpenCC so every final transcript runs through s2hk.",
          systemImage: "character.book.closed.fill"
        ))
    }
    if diagnostics.isEmpty {
      diagnostics.append(
        SetupDiagnostic(
          id: .ready,
          title: "Ready",
          detail: "Keys and required permissions look ready.",
          systemImage: "checkmark.circle.fill"
        ))
    }
    return diagnostics
  }

  private func permissionState(for permission: AppPermission) -> PermissionState? {
    permissions.first(where: { $0.permission == permission })?.state
  }
}

/// Identifies each setup issue consistently across readiness summaries and their corrective actions.
struct SetupDiagnostic: Identifiable, Sendable {
  enum ID: Hashable, Sendable {
    case transcriptionConfiguration
    case providerKey
    case microphonePermission
    case accessibilityPermission
    case adjustmentKey
    case screenPermission
    case openCC
    case ready
  }

  let id: ID
  let title: String
  let detail: String
  let systemImage: String

  var severity: SetupDiagnosticSeverity {
    id == .ready ? .ready : .attention
  }
}

enum SetupDiagnosticSeverity: Equatable, Sendable {
  case ready
  case attention
}
