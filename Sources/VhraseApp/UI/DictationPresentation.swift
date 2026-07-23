// Maps Vhrase's workflow and readiness state into consistent UI-facing copy and actions.

import Foundation
import SwiftUI

/// Owns reusable display policy shared by Vhrase's compact and full-window UI surfaces.
struct DictationPresentation {
    let status: AppStatus
    let settings: DictationSettings
    let xaiAPIKey: String
    let elevenLabsAPIKey: String
    let permissions: [PermissionSnapshot]
    let liveTranscript: String
    let recordingElapsedSeconds: Int
    let delivery: TranscriptDelivery

    init(
        status: AppStatus,
        settings: DictationSettings,
        xaiAPIKey: String,
        elevenLabsAPIKey: String,
        permissions: [PermissionSnapshot],
        liveTranscript: String,
        recordingElapsedSeconds: Int,
        delivery: TranscriptDelivery = .none
    ) {
        self.status = status
        self.settings = settings
        self.xaiAPIKey = xaiAPIKey
        self.elevenLabsAPIKey = elevenLabsAPIKey
        self.permissions = permissions
        self.liveTranscript = liveTranscript
        self.recordingElapsedSeconds = recordingElapsedSeconds
        self.delivery = delivery
    }

    var selectedProviderHasKey: Bool {
        switch settings.provider {
        case .xai:
            !xaiAPIKey.isEmpty
        case .elevenLabs:
            !elevenLabsAPIKey.isEmpty
        }
    }

    var selectedWorkflowReady: Bool {
        coreRecordingReady
            && (!settings.adjustWithLLM || !settings.includeScreenshot || permissionIsReady(.screenRecording))
            && permissionIsReady(.accessibility)
    }

    var coreRecordingReady: Bool {
        selectedProviderHasKey && permissionIsReady(.microphone)
    }

    /// Reports whether the selected shortcut can receive global key events with the current permissions.
    var selectedShortcutReady: Bool {
        settings.hotkeyPreset != .fn
            || permissionIsReady(.inputMonitoring)
            || permissionIsReady(.accessibility)
    }

    var needsAccessibilityForInsertion: Bool {
        !permissionIsReady(.accessibility)
    }

    var insertionPermissionActionTitle: String? {
        guard needsAccessibilityForInsertion,
              let snapshot = permissionSnapshot(.accessibility) else {
            return nil
        }
        return snapshot.requestedBefore ? "Open Accessibility" : "Enable Insertion"
    }

    var workflowControlsAreDisabled: Bool {
        !status.canStartRecording
    }

    var readinessTitle: String {
        selectedWorkflowReady ? "Ready to record" : "Needs attention"
    }

    var elapsedTime: String {
        let minutes = recordingElapsedSeconds / 60
        let seconds = recordingElapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var compactWorkflowSummary: String {
        "\(settings.provider.title) \(settings.transcriptionMode.title.lowercased()) · \(settings.hotkeyDisplay) \(settings.shortcutBehavior.title.lowercased())"
    }

    var fullWorkflowSummary: String {
        "\(settings.provider.title) \(settings.transcriptionMode.title.lowercased()) · \(settings.adjustWithLLM ? "LLM cleanup" : "Raw")"
    }

    var statusShortTitle: String {
        switch status {
        case .idle:
            if !coreRecordingReady {
                "Needs setup"
            } else if !selectedShortcutReady {
                "Shortcut setup"
            } else {
                "Ready"
            }
        case .preparing:
            "Starting"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        case .adjusting:
            "Adjusting"
        case .completed:
            "Done"
        case .failed:
            "Failed"
        }
    }

    var displayStatusTitle: String {
        switch status {
        case .idle:
            if !coreRecordingReady {
                "Needs setup"
            } else if !selectedShortcutReady {
                "Shortcut setup"
            } else {
                "Ready"
            }
        case .preparing:
            "Starting"
        case .recording:
            "Listening"
        case .transcribing:
            "Transcribing"
        case .adjusting:
            "Cleaning up"
        case .completed:
            delivery.completionTitle
        case .failed:
            "Couldn't finish"
        }
    }

    var statusTint: Color {
        switch status {
        case .recording:
            VhraseTheme.statusRecording
        case .completed:
            delivery == .none ? VhraseTheme.statusWarning : VhraseTheme.statusSuccess
        case .failed:
            VhraseTheme.statusFailure
        case .preparing, .transcribing, .adjusting:
            VhraseTheme.statusProcessing
        case .idle:
            coreRecordingReady && selectedShortcutReady
                ? VhraseTheme.inkSecondary
                : VhraseTheme.statusWarning
        }
    }

    var statusSystemImage: String {
        switch status {
        case .failed:
            "exclamationmark.triangle.fill"
        case .preparing:
            "mic.badge.plus"
        case .recording:
            "waveform.circle.fill"
        case .transcribing, .adjusting:
            "clock.fill"
        case .completed:
            "checkmark.circle.fill"
        case .idle:
            if !selectedProviderHasKey {
                "key.fill"
            } else if !permissionIsReady(.microphone) {
                "mic.slash.fill"
            } else if !selectedShortcutReady {
                "keyboard.badge.ellipsis"
            } else {
                "checkmark.circle"
            }
        }
    }

    var statusMessage: String? {
        if case .failed(let message) = status {
            return message
        }
        if !selectedProviderHasKey, !isRecording {
            return "Add \(settings.provider.title) API key in System before recording."
        }
        if !permissionIsReady(.microphone), status.canStartRecording {
            return "Grant Microphone access before recording."
        }
        return nil
    }

    var statusMessageIcon: String {
        if case .failed = status {
            return "exclamationmark.triangle"
        }
        if !permissionIsReady(.microphone) {
            return "mic.slash"
        }
        return "key"
    }

    var recordAction: RecordAction {
        if isPreparing {
            return .cancelRecording
        }
        if isRecording {
            return .toggleRecording
        }
        guard status.canStartRecording else {
            return .disabled
        }
        return coreRecordingReady ? .toggleRecording : .openSetup
    }

    var recordButtonSystemImage: String {
        if isPreparing {
            return "xmark"
        }
        if isRecording {
            return "stop.fill"
        }
        if !selectedProviderHasKey {
            return "key.fill"
        }
        if !permissionIsReady(.microphone) {
            return "mic.slash.fill"
        }
        return "mic.fill"
    }

    var recordButtonTitle: String {
        if isPreparing {
            return "Cancel"
        }
        if isRecording {
            return "Stop and Transcribe"
        }
        if !selectedProviderHasKey {
            return "Add \(settings.provider.title) Key"
        }
        if !permissionIsReady(.microphone) {
            return "Set Up Microphone"
        }
        if status.isProcessing {
            return "Processing…"
        }
        return "Start Recording"
    }

    func recordButtonSubtitle(style: RecordSubtitleStyle) -> String {
        if isPreparing {
            return "Starting microphone…"
        }
        if !selectedProviderHasKey {
            switch style {
            case .compact:
                return "Keys are saved locally"
            case .full:
                return "Keys save locally"
            }
        }
        if !permissionIsReady(.microphone) {
            return "Microphone permission is required"
        }
        if status.isProcessing {
            switch style {
            case .compact:
                return "\(settings.provider.title) \(settings.transcriptionMode.title.lowercased()) is processing"
            case .full:
                return "\(settings.provider.title) is working"
            }
        }
        switch style {
        case .compact:
            let cleanup = settings.adjustWithLLM ? "LLM cleanup" : "Raw"
            return "\(settings.provider.title) \(settings.transcriptionMode.title.lowercased()) · \(cleanup) · \(settings.shortcutBehavior.summary)"
        case .full:
            return "\(settings.hotkeyDisplay) · \(settings.shortcutBehavior.summary)"
        }
    }

    var compactLiveTranscriptText: String {
        if !liveTranscript.isEmpty {
            return liveTranscript
        }
        return recordingPlaceholderText
    }

    var fullLiveTranscriptText: String {
        if !liveTranscript.isEmpty {
            return liveTranscript
        }
        if isRecording {
            return recordingPlaceholderText
        }
        return "Live recording details will appear here while you speak."
    }

    func permissionIsReady(_ permission: AppPermission) -> Bool {
        permissionSnapshot(permission)?.state.isReady ?? false
    }

    func permissionStateTitle(_ permission: AppPermission) -> String {
        permissionSnapshot(permission)?.displayTitle ?? "Unknown"
    }

    func permissionSnapshot(_ permission: AppPermission) -> PermissionSnapshot? {
        permissions.first { $0.permission == permission }
    }

    func historyMetadata(
        _ item: TranscriptHistoryItem,
        relativeTo date: Date? = Date()
    ) -> String {
        let target = item.targetAppName.map { "→ \($0)" }
        let dateLabel = date.map { relativeDateLabel(for: item.createdAt, relativeTo: $0) }
        return [dateLabel, item.provider, item.transcriptionMode, item.cleanup.title, target]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var isRecording: Bool {
        if case .recording = status {
            return true
        }
        return false
    }

    private var isPreparing: Bool {
        if case .preparing = status {
            return true
        }
        return false
    }

    private var recordingPlaceholderText: String {
        settings.transcriptionMode == .realtime ? "Listening for realtime transcript…" : "Recording audio for upload transcription…"
    }

    private func relativeDateLabel(
        for createdAt: Date,
        relativeTo date: Date
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: date)
    }
}

enum RecordAction: Equatable {
    case toggleRecording
    case cancelRecording
    case openSetup
    case disabled
}

enum RecordSubtitleStyle {
    case compact
    case full
}

extension TranscriptDelivery {
    var completionTitle: String {
        switch self {
        case .pasteCommandSent:
            "Paste sent"
        case .copied:
            "Copied"
        case .none:
            "Saved"
        }
    }

    var completionDetail: String {
        switch self {
        case .pasteCommandSent(let clipboardRetained):
            clipboardRetained
                ? "The paste command was sent, and the transcript remains on the clipboard."
                : "The paste command was sent without keeping the transcript on the clipboard."
        case .copied:
            "The transcript was copied to the clipboard."
        case .none:
            "The transcript was saved to history, but clipboard delivery failed."
        }
    }

    var completionSystemImage: String {
        switch self {
        case .pasteCommandSent:
            "checkmark.circle.fill"
        case .copied:
            "doc.on.clipboard.fill"
        case .none:
            "exclamationmark.triangle.fill"
        }
    }
}
