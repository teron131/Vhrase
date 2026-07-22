// Derives actionable setup diagnostics from settings, credentials, and macOS permission state.

import Foundation

struct SetupDiagnostics {
    let settings: DictationSettings
    let xaiAPIKey: String
    let elevenLabsAPIKey: String
    let llmAPIKey: String
    let permissions: [PermissionSnapshot]
    let chineseConversionIsAvailable: Bool

    func build() -> [SetupDiagnostic] {
        var diagnostics: [SetupDiagnostic] = []

        if let issue = transcriptionConfigurationIssue {
            diagnostics.append(diagnostic(
                id: "transcription-configuration",
                title: "Transcription settings",
                detail: issue,
                systemImage: "slider.horizontal.3"
            ))
        }
        if selectedProviderKeyIsMissing {
            diagnostics.append(diagnostic(
                id: "selected-provider-key",
                title: "\(settings.provider.title) key",
                detail: "Add the selected STT provider key in Settings.",
                systemImage: "key.fill"
            ))
        }
        if permissionState(for: .microphone)?.isReady != true {
            diagnostics.append(diagnostic(
                id: "microphone-permission",
                title: "Microphone",
                detail: "Grant mic access before real recording.",
                systemImage: "mic.fill"
            ))
        }
        if settings.hotkeyPreset == .fn, permissionState(for: .inputMonitoring)?.isReady != true {
            diagnostics.append(diagnostic(
                id: "input-monitoring-permission",
                title: "Fn/Globe shortcut",
                detail: "Grant Input Monitoring so Fn/Globe works outside Vhrase.",
                systemImage: "keyboard"
            ))
        }
        if settings.adjustWithLLM, llmAPIKey.isEmpty {
            diagnostics.append(diagnostic(
                id: "adjustment-key",
                title: "LLM adjustment",
                detail: "LLM API key is required for transcript cleanup.",
                systemImage: "wand.and.stars"
            ))
        }
        if settings.adjustWithLLM,
           settings.includeScreenshot,
           permissionState(for: .screenRecording)?.isReady != true {
            diagnostics.append(diagnostic(
                id: "screen-permission",
                title: "Screenshot context",
                detail: "Grant Screen Recording or turn screenshot off.",
                systemImage: "rectangle.on.rectangle"
            ))
        }
        if settings.pasteAfterTranscription,
           permissionState(for: .accessibility)?.isReady != true {
            diagnostics.append(SetupDiagnostic(
                id: "accessibility-permission",
                title: "Paste insertion",
                detail: "Accessibility may be needed to paste into other apps.",
                systemImage: "cursorarrow.motionlines",
                severity: .info
            ))
        }
        if !chineseConversionIsAvailable {
            diagnostics.append(diagnostic(
                id: "opencc-s2hk",
                title: "OpenCC s2hk",
                detail: "Install OpenCC so every final transcript runs through s2hk.",
                systemImage: "character.book.closed.fill"
            ))
        }
        if diagnostics.isEmpty {
            diagnostics.append(SetupDiagnostic(
                id: "ready",
                title: "Ready",
                detail: "Keys and required permissions look ready.",
                systemImage: "checkmark.circle.fill",
                severity: .ready
            ))
        }
        return diagnostics
    }

    private var transcriptionConfigurationIssue: String? {
        do {
            try TranscriptionContract.validate(settings: settings)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var selectedProviderKeyIsMissing: Bool {
        switch settings.provider {
        case .xai: xaiAPIKey.isEmpty
        case .elevenLabs: elevenLabsAPIKey.isEmpty
        }
    }

    private func permissionState(for permission: AppPermission) -> PermissionState? {
        permissions.first(where: { $0.permission == permission })?.state
    }

    private func diagnostic(
        id: String,
        title: String,
        detail: String,
        systemImage: String
    ) -> SetupDiagnostic {
        SetupDiagnostic(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            severity: .attention
        )
    }
}
