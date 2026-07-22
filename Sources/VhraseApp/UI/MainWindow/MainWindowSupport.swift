// Centralizes display policy and reusable controls for Vhrase's main-window destinations.

import AppKit
import Foundation
import SwiftUI

extension MainWindowView {
    var presentation: DictationPresentation {
        DictationPresentation(
            status: appState.status,
            settings: appState.settings,
            xaiAPIKey: appState.effectiveXAIAPIKey,
            elevenLabsAPIKey: appState.effectiveElevenLabsAPIKey,
            permissions: appState.permissions,
            liveTranscript: appState.liveTranscript,
            recordingElapsedSeconds: appState.recordingElapsedSeconds
        )
    }

    var audioMeter: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(appState.isRecording ? Color.red : Color.accentColor)
                    .frame(
                        width: max(
                            8,
                            proxy.size.width * min(max(appState.recordingLevel, 0), 1)
                        )
                    )
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    var transcriptWorkspaceTitle: String {
        if hasInterruptedLiveTranscript {
            return "Interrupted transcript"
        }
        return showsLiveCapture ? "Live transcript" : "Latest transcript"
    }

    var transcriptWorkspaceSystemImage: String {
        if hasInterruptedLiveTranscript {
            return "exclamationmark.bubble"
        }
        return showsLiveCapture ? statusSystemImage : "text.quote"
    }

    var transcriptWorkspaceSubtitle: String {
        if hasInterruptedLiveTranscript {
            return "Partial realtime text captured before the failure"
        }
        return switch appState.status {
        case .preparing:
            "Getting the microphone ready"
        case .recording:
            appState.settings.transcriptionMode == .realtime
                ? "Updates while you speak"
                : "Transcribes after you stop"
        case .transcribing:
            "Audio captured · \(appState.settings.provider.title) is working"
        case .adjusting:
            "Applying your writing preferences"
        case .idle, .completed, .failed:
            "Your most recent completed dictation"
        }
    }

    var transcriptWorkspaceText: String {
        if hasInterruptedLiveTranscript {
            return appState.liveTranscript
        }
        return switch appState.status {
        case .preparing:
            "Starting microphone…"
        case .recording:
            liveTranscriptText
        case .transcribing:
            appState.liveTranscript.isEmpty
                ? "Audio captured. Waiting for \(appState.settings.provider.title) to return the transcript…"
                : appState.liveTranscript
        case .adjusting:
            appState.liveTranscript.isEmpty
                ? "Transcript received. Applying your writing preferences…"
                : appState.liveTranscript
        case .idle, .completed, .failed:
            appState.lastTranscript.isEmpty ? "Your next transcript will appear here." : appState.lastTranscript
        }
    }

    var transcriptWorkspaceIsPlaceholder: Bool {
        if hasInterruptedLiveTranscript {
            return false
        }
        switch appState.status {
        case .preparing, .recording, .transcribing, .adjusting:
            return appState.liveTranscript.isEmpty
        case .idle, .completed, .failed:
            return appState.lastTranscript.isEmpty
        }
    }

    var transcriptWorkspaceCopyText: String {
        hasInterruptedLiveTranscript ? appState.liveTranscript : appState.lastTranscript
    }

    var transcriptWorkspaceCopyTitle: String {
        hasInterruptedLiveTranscript ? "Copy partial" : "Copy"
    }

    var transcriptWorkspaceShowsCopyAction: Bool {
        hasInterruptedLiveTranscript || !showsLiveCapture
    }

    private var hasInterruptedLiveTranscript: Bool {
        guard !appState.liveTranscript.isEmpty else {
            return false
        }
        switch appState.status {
        case .failed, .idle:
            return true
        case .preparing, .recording, .transcribing, .adjusting, .completed:
            return false
        }
    }

    var primarySetupDiagnostic: SetupDiagnostic {
        appState.setupDiagnostics.first { $0.severity == .attention }
            ?? appState.setupDiagnostics.first { $0.severity == .info }
            ?? appState.setupDiagnostics.first
            ?? SetupDiagnostic(
                id: "ready",
                title: "Ready",
                detail: "Vhrase is ready to record.",
                systemImage: "checkmark.circle.fill",
                severity: .ready
            )
    }

    var setupOverviewTitle: String {
        switch primarySetupDiagnostic.id {
        case "ready", "opencc-s2hk":
            "Ready to dictate"
        case "input-monitoring-permission", "screen-permission", "accessibility-permission":
            "Recording is ready"
        default:
            "Finish setup"
        }
    }

    var setupOverviewDetail: String {
        switch primarySetupDiagnostic.id {
        case "ready":
            "The selected provider and required permissions are ready."
        case "opencc-s2hk", "input-monitoring-permission", "screen-permission", "accessibility-permission":
            "Core recording works. \(primarySetupDiagnostic.detail)"
        default:
            primarySetupDiagnostic.detail
        }
    }

    func setupDiagnosticActionTitle(_ diagnostic: SetupDiagnostic) -> String? {
        switch diagnostic.id {
        case "transcription-configuration":
            "Review Writing"
        case "selected-provider-key", "adjustment-key":
            "Add Key"
        case "microphone-permission":
            "Request Access"
        case "input-monitoring-permission":
            presentation.permissionSnapshot(.inputMonitoring)?.requestedBefore == true
                ? "Open Settings"
                : "Enable Shortcut"
        case "screen-permission", "accessibility-permission":
            "Open Settings"
        case "opencc-s2hk", "ready":
            nil
        default:
            nil
        }
    }

    /// Routes the leading setup issue to the existing configuration or macOS permission action.
    func handleSetupDiagnostic(_ diagnostic: SetupDiagnostic) {
        switch diagnostic.id {
        case "transcription-configuration":
            selectedTab = .customize
        case "selected-provider-key":
            focusedSecretField = switch appState.settings.provider {
            case .xai:
                SecretKey.xaiAPIKey.rawValue
            case .elevenLabs:
                SecretKey.elevenLabsAPIKey.rawValue
            }
        case "adjustment-key":
            focusedSecretField = SecretKey.llmAPIKey.rawValue
        case "microphone-permission":
            if let snapshot = presentation.permissionSnapshot(.microphone) {
                appState.handlePermissionAction(snapshot)
            } else {
                appState.setupPermissionsOnce()
            }
        case "input-monitoring-permission":
            if let snapshot = presentation.permissionSnapshot(.inputMonitoring) {
                appState.handlePermissionAction(snapshot)
            }
        case "screen-permission":
            if let snapshot = presentation.permissionSnapshot(.screenRecording) {
                appState.handlePermissionAction(snapshot)
            }
        case "accessibility-permission":
            if let snapshot = presentation.permissionSnapshot(.accessibility) {
                appState.handlePermissionAction(snapshot)
            }
        case "opencc-s2hk", "ready":
            break
        default:
            break
        }
    }

    func labeledPicker<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent(title) {
            content()
                .frame(maxWidth: 240)
        }
    }

    func compactField(
        _ title: String,
        text: Binding<String>
    ) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
        }
    }

    func editorTile(
        _ title: String,
        systemImage: String,
        text: Binding<String>,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            TextEditor(text: text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .frame(minHeight: height, maxHeight: height)
                .padding(8)
                .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(title)
        }
    }

    func keyStatus(
        _ title: String,
        isReady: Bool,
        usesEnvironmentOverride: Bool
    ) -> some View {
        Label(
            usesEnvironmentOverride
                ? "\(title) from environment"
                : (isReady ? "\(title) ready" : "\(title) missing"),
            systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.callout)
        .foregroundStyle(isReady ? Color.green : Color.orange)
    }

    func permissionTile(_ snapshot: PermissionSnapshot) -> some View {
        Button {
            appState.handlePermissionAction(snapshot)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: snapshot.permission.systemImage)
                    .font(.title3)
                    .frame(width: 24)
                    .foregroundStyle(snapshot.state.isReady ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.permission.title)
                        .font(.headline)
                    Text(snapshot.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHint(snapshot.state.isReady ? "Opens macOS permission settings" : "Requests access or opens macOS permission settings")
    }
}

extension MainWindowView {
    var statusShortTitle: String {
        if appState.status == .completed {
            return appState.lastDelivery.completionTitle
        }
        return presentation.statusShortTitle
    }

    var statusDetail: String {
        switch appState.status {
        case .idle:
            if !selectedProviderHasKey {
                return "Add the selected provider key before recording."
            }
            if !presentation.permissionIsReady(.microphone) {
                return "Grant Microphone access before recording."
            }
            return "Ready for \(workflowSummary)."
        case .preparing:
            return "Starting the microphone and preparing \(appState.settings.provider.title)."
        case .recording:
            if appState.settings.shortcutBehavior == .holdToRecord {
                return "Listening. Release \(appState.settings.hotkeyDisplay) to transcribe."
            }
            return "Listening. Press \(appState.settings.hotkeyDisplay) again when you are done."
        case .transcribing:
            return "Transcribing with \(appState.settings.provider.title)."
        case .adjusting:
            return "Cleaning up the transcript."
        case .completed:
            return appState.lastDelivery.completionDetail
        case .failed(let message):
            return message
        }
    }

    var statusSystemImage: String {
        if appState.status == .completed {
            return appState.lastDelivery.completionSystemImage
        }
        return presentation.statusSystemImage
    }

    var statusColor: Color {
        switch appState.status {
        case .failed:
            return .red
        case .recording:
            return .red
        case .completed:
            return appState.lastDelivery == .none ? .orange : .green
        case .idle:
            return presentation.coreRecordingReady ? .secondary : .orange
        case .preparing, .transcribing, .adjusting:
            return .accentColor
        }
    }

    var recordButtonSystemImage: String {
        presentation.recordButtonSystemImage
    }

    var recordButtonTitle: String {
        presentation.recordButtonTitle
    }

    var recordButtonSubtitle: String {
        presentation.recordButtonSubtitle(style: .full)
    }

    var recordButtonTint: Color {
        switch appState.status {
        case .preparing, .recording:
            return .red
        case .failed:
            return .red
        default:
            return .accentColor
        }
    }

    var selectedProviderHasKey: Bool {
        presentation.selectedProviderHasKey
    }

    var workflowSummary: String {
        presentation.fullWorkflowSummary
    }

    var elapsedTime: String {
        presentation.elapsedTime
    }

    var liveTranscriptText: String {
        presentation.fullLiveTranscriptText
    }

    var showsLiveCapture: Bool {
        if !appState.liveTranscript.isEmpty {
            return true
        }
        switch appState.status {
        case .preparing, .recording, .transcribing, .adjusting:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var filteredHistory: [TranscriptHistoryItem] {
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return appState.history
        }
        return appState.history.filter { item in
            item.text.localizedCaseInsensitiveContains(query)
                || item.provider.localizedCaseInsensitiveContains(query)
                || item.transcriptionMode.localizedCaseInsensitiveContains(query)
                || item.cleanup.title.localizedCaseInsensitiveContains(query)
                || item.targetAppName?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var keytermGuidance: String {
        if let issue = appState.transcriptionConfigurationIssue {
            return issue
        }
        switch (appState.settings.provider, appState.settings.transcriptionMode) {
        case (.xai, _):
            return "xAI accepts up to 100 keyterms, with at most 50 characters in each term."
        case (.elevenLabs, .upload):
            return "ElevenLabs upload accepts up to 1,000 keyterms; using keyterms adds 20% to transcription usage."
        case (.elevenLabs, .realtime):
            return "ElevenLabs realtime accepts up to 50 keyterms of 20 characters each; using keyterms adds 20% to transcription usage."
        }
    }

    func handleRecordButton() {
        switch presentation.recordAction {
        case .toggleRecording:
            appState.toggleRecording()
        case .cancelRecording:
            appState.cancelRecording()
        case .openSetup:
            selectedTab = .setup
        case .disabled:
            break
        }
    }

    func cancelShortcutCaptureIfNeeded() {
        guard isCapturingHotkey else {
            return
        }
        isCapturingHotkey = false
        appState.cancelShortcutCapture()
    }

    func diagnosticColor(_ severity: SetupDiagnosticSeverity) -> Color {
        switch severity {
        case .ready:
            return .green
        case .attention:
            return .orange
        case .info:
            return .secondary
        }
    }

    func historyMetadata(_ item: TranscriptHistoryItem) -> String {
        presentation.historyMetadata(item)
    }

    func persistedBinding<Value>(
        _ keyPath: WritableKeyPath<DictationSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                appState.settings[keyPath: keyPath]
            },
            set: { value in
                appState.updateSettings { settings in
                    settings[keyPath: keyPath] = value
                }
            }
        )
    }

    func apiKeyBinding(
        _ key: SecretKey,
        _ keyPath: ReferenceWritableKeyPath<AppState, String>
    ) -> Binding<String> {
        Binding(
            get: {
                appState[keyPath: keyPath]
            },
            set: { value in
                appState[keyPath: keyPath] = value
                scheduleAPIKeySave(key)
            }
        )
    }

    func scheduleAPIKeySave(_ key: SecretKey) {
        pendingAPIKeySaves.insert(key)
        apiKeySaveTask?.cancel()
        apiKeySaveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            apiKeySaveTask = nil
            let keys = pendingAPIKeySaves
            pendingAPIKeySaves.removeAll()
            appState.saveAPIKeys(keys)
        }
    }

    func flushPendingAPIKeySave() {
        guard apiKeySaveTask != nil else {
            return
        }
        apiKeySaveTask?.cancel()
        apiKeySaveTask = nil
        let keys = pendingAPIKeySaves
        pendingAPIKeySaves.removeAll()
        appState.saveAPIKeys(keys)
    }
}
