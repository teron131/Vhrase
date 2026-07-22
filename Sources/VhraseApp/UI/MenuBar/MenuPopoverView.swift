// Provides Vhrase's capture-first menu-bar controls and routes review or setup work to dedicated windows.

import AppKit
import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var presentation: DictationPresentation {
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

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                header
                recordButton
                statusMessagePanel

                if showsLiveWorkflow {
                    liveTranscriptPanel
                } else {
                    recentTranscripts
                }

                captureConfiguration

                if primarySetupDiagnostic.severity != .ready {
                    setupSummary
                }
            }
            .padding(15)

            Divider()

            footer
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
        }
        .frame(width: 336)
        .onAppear {
            appState.refreshPermissions()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Vhrase")
                    .font(.headline)
                Text(presentation.compactWorkflowSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Label(menuStatusTitle, systemImage: menuStatusSystemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .labelStyle(.titleAndIcon)
                .accessibilityElement(children: .combine)
        }
    }

    private var recordButton: some View {
        Button {
            handleRecordButton()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: presentation.recordButtonSystemImage)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 22)

                Text(presentation.recordButtonTitle)
                    .font(.callout.weight(.semibold))

                Spacer()

                if appState.isRecording {
                    Text(presentation.elapsedTime)
                        .font(.caption.monospacedDigit().weight(.medium))
                } else {
                    Text(appState.settings.hotkeyDisplay)
                        .font(.caption.monospaced().weight(.medium))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(recordButtonTint)
        .disabled(presentation.recordAction == .disabled)
        .accessibilityHint(presentation.recordButtonSubtitle(style: .compact))
    }

    @ViewBuilder
    private var statusMessagePanel: some View {
        if appState.status == .completed {
            compactNotice(
                appState.lastDelivery.completionDetail,
                systemImage: appState.lastDelivery.completionSystemImage,
                color: statusColor
            )
        } else if let message = presentation.statusMessage {
            compactNotice(
                message,
                systemImage: presentation.statusMessageIcon,
                color: statusMessageColor
            )
        }
    }

    private var liveTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(menuStatusTitle, systemImage: menuStatusSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)

                Spacer()

                if !appState.targetAppLabel.isEmpty {
                    Text("→ \(appState.targetAppLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if appState.isRecording {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                        Capsule()
                            .fill(Color.red)
                            .frame(
                                width: max(
                                    8,
                                    proxy.size.width * min(max(appState.recordingLevel, 0), 1)
                                )
                            )
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }

            Text(liveTranscriptText)
                .font(.callout)
                .foregroundStyle(appState.liveTranscript.isEmpty ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(AppTheme.field.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.hairline.opacity(0.5), lineWidth: 1)
        }
    }

    private var recentTranscripts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("History") {
                    openMainWindow(.history)
                }
                .buttonStyle(.link)
                .accessibilityHint("Opens all saved transcripts")
            }

            if recentHistory.isEmpty {
                Text("Your latest dictations will stay within reach here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
            } else {
                ForEach(recentHistory) { item in
                    recentTranscriptRow(item)
                }
            }
        }
    }

    private func recentTranscriptRow(_ item: TranscriptHistoryItem) -> some View {
        Button {
            appState.copyHistoryItem(item)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "text.quote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(presentation.historyMetadata(item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(9)
            .background(AppTheme.field.opacity(0.54), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy transcript")
        .accessibilityHint("Copies this transcript to the clipboard")
    }

    private var captureConfiguration: some View {
        HStack(spacing: 8) {
            Label("Capture", systemImage: "slider.horizontal.2.square")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Provider", selection: persistedBinding(\.provider)) {
                ForEach(STTProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Transcription provider")

            Picker("Mode", selection: persistedBinding(\.transcriptionMode)) {
                ForEach(TranscriptionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Transcription mode")
        }
        .disabled(presentation.workflowControlsAreDisabled)
    }

    private var setupSummary: some View {
        Button {
            openMainWindow(.setup)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: primarySetupDiagnostic.systemImage)
                    .foregroundStyle(diagnosticColor(primarySetupDiagnostic.severity))
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primarySetupDiagnostic.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(primarySetupDiagnostic.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens setup in the main Vhrase window")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                openMainWindow()
            } label: {
                Label("Home", systemImage: "macwindow")
            }
            .buttonStyle(.borderless)

            Button {
                openMainWindow(.history)
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)

            Button {
                NSApplication.shared.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")

            Spacer()

            Button {
                appState.prepareForTermination()
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Vhrase")
            .accessibilityLabel("Quit Vhrase")
        }
    }

    private var recentHistory: [TranscriptHistoryItem] {
        Array(appState.history.prefix(2))
    }

    private var showsLiveWorkflow: Bool {
        switch appState.status {
        case .preparing, .recording, .transcribing, .adjusting:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    private var liveTranscriptText: String {
        switch appState.status {
        case .preparing:
            return "Starting microphone…"
        case .recording:
            return presentation.compactLiveTranscriptText
        case .transcribing:
            return appState.liveTranscript.isEmpty
                ? "Audio captured. Waiting for \(appState.settings.provider.title)…"
                : appState.liveTranscript
        case .adjusting:
            return appState.liveTranscript.isEmpty
                ? "Applying your writing preferences…"
                : appState.liveTranscript
        case .idle, .completed, .failed:
            return appState.lastTranscript
        }
    }

    private var menuStatusTitle: String {
        appState.status == .completed ? appState.lastDelivery.completionTitle : presentation.statusShortTitle
    }

    private var menuStatusSystemImage: String {
        appState.status == .completed ? appState.lastDelivery.completionSystemImage : presentation.statusSystemImage
    }

    private var primarySetupDiagnostic: SetupDiagnostic {
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

    private var statusColor: Color {
        switch appState.status {
        case .failed, .recording:
            return .red
        case .completed:
            return appState.lastDelivery == .none ? .orange : .green
        case .idle:
            return presentation.coreRecordingReady ? .secondary : .orange
        case .preparing, .transcribing, .adjusting:
            return .accentColor
        }
    }

    private var statusMessageColor: Color {
        if case .failed = appState.status {
            return .red
        }
        return .orange
    }

    private var recordButtonTint: Color {
        switch appState.status {
        case .preparing, .recording:
            return .red
        default:
            return .accentColor
        }
    }

    private func compactNotice(
        _ text: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private func handleRecordButton() {
        switch presentation.recordAction {
        case .toggleRecording:
            appState.toggleRecording()
        case .cancelRecording:
            appState.cancelRecording()
        case .openSetup:
            openMainWindow(.setup)
        case .disabled:
            break
        }
    }

    private func openMainWindow(_ tab: MainWindowTab = .dictation) {
        UserDefaults.standard.set(tab.rawValue, forKey: "mainWindow.selectedTab")
        openWindow(id: "main")
        DispatchQueue.main.async {
            NSApplication.shared.activate()
        }
    }

    private func diagnosticColor(_ severity: SetupDiagnosticSeverity) -> Color {
        switch severity {
        case .ready:
            return .green
        case .attention:
            return .orange
        case .info:
            return .secondary
        }
    }

    private func persistedBinding<Value>(
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
}
