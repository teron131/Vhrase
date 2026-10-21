// Derives actionable setup diagnostics from settings, credentials, the on-device model, and macOS permission state.

import Foundation

enum ProviderReadiness: Equatable, Sendable {
  case ready
  case missingAPIKey
  case missingLocalModel
}

struct SetupDiagnostics {
  let settings: DictationSettings
  let providerReadiness: ProviderReadiness
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
    switch providerReadiness {
    case .ready:
      break
    case .missingAPIKey:
      diagnostics.append(
        SetupDiagnostic(
          id: .providerKey,
          title: "\(settings.provider.title) key",
          detail: "Add your \(settings.provider.title) API key to start transcribing.",
          systemImage: "key.fill"
        ))
    case .missingLocalModel:
      diagnostics.append(
        SetupDiagnostic(
          id: .localModel,
          title: "\(settings.provider.title) model",
          detail:
            "Download the model once. Recognition then runs on this Mac without a network connection.",
          systemImage: "arrow.down.circle.fill"
        ))
    }
    if permissionState(for: .microphone)?.isReady != true {
      diagnostics.append(
        SetupDiagnostic(
          id: .microphonePermission,
          title: "Microphone",
          detail: "Allow microphone access so Vhrase can hear you.",
          systemImage: "mic.fill"
        ))
    }
    let accessibilityIsReady = permissionState(for: .accessibility)?.isReady == true
    if !accessibilityIsReady {
      diagnostics.append(
        SetupDiagnostic(
          id: .accessibilityPermission,
          title: settings.hotkeyPreset == .fn ? "Shortcut and pasting" : "Pasting into apps",
          detail: settings.hotkeyPreset == .fn
            ? "Allow Accessibility so Fn/Globe works everywhere and text pastes where you were typing."
            : "Allow Accessibility so text pastes where you were typing.",
          systemImage: "cursorarrow.motionlines"
        ))
    }
    if settings.adjustWithLLM, !hasLLMKey {
      diagnostics.append(
        SetupDiagnostic(
          id: .adjustmentKey,
          title: "LLM key",
          detail: "Add an LLM API key, or turn off automatic polishing.",
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
          title: "Screen context",
          detail: "Allow Screen Recording, or turn off screen context.",
          systemImage: "rectangle.on.rectangle"
        ))
    }
    if settings.convertChineseOutput, !chineseConversionIsAvailable {
      diagnostics.append(
        SetupDiagnostic(
          id: .openCC,
          title: "Chinese output",
          detail: "Install OpenCC to convert Chinese to Traditional.",
          systemImage: "character.book.closed.fill"
        ))
    }
    if diagnostics.isEmpty {
      diagnostics.append(
        SetupDiagnostic(
          id: .ready,
          title: "Ready",
          detail: settings.provider.location == .local
            ? "The on-device model and required permissions look ready."
            : "Keys and required permissions look ready.",
          systemImage: "checkmark.circle.fill"
        ))
    }
    return diagnostics
  }

  private func permissionState(for permission: AppPermission) -> PermissionState? {
    permissions.first(where: { $0.permission == permission })?.state
  }
}

struct SetupDiagnostic: Identifiable, Sendable {
  enum ID: Hashable, Sendable {
    case transcriptionConfiguration
    case providerKey
    case localModel
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
