// Presents Vhrase's live workflow in a focus-preserving recorder HUD owned by an AppKit panel.

import AppKit
import Combine
import SwiftUI

/// Displays the current dictation phase without exposing transport-level implementation details.
struct StatusPopupView: View {
    @ObservedObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: DictationPresentation {
        appState.presentation
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar

            if showsTranscript {
                Divider()
                    .opacity(0.45)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(detailIsPlaceholder ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityLabel(detailText)
            }
        }
        .frame(width: popupWidth, height: popupHeight)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
        .fixedSize(horizontal: true, vertical: true)
        .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
            value: showsTranscript
        )
    }

    private var controlBar: some View {
        HStack(spacing: 11) {
            statusIndicator
                .frame(width: appState.isRecording ? 96 : 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(popupStatusTitle)
                    .font(appState.isRecording ? VhraseFont.timer : .callout.weight(.semibold))
                    .lineLimit(1)
                Text(secondaryStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch appState.status {
        case .preparing, .transcribing, .adjusting:
            ProgressView()
                .controlSize(.small)
                .tint(statusColor)
                .accessibilityHidden(true)
        case .recording:
            WaveformView(
                level: appState.recordingLevel,
                response: .live,
                barCount: 20,
                tint: VhraseTheme.statusRecording,
                height: 28
            )
        case .completed, .failed, .idle:
            Image(systemName: popupStatusSystemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch appState.status {
            case .preparing:
                hudButton("Cancel", systemImage: "xmark") {
                    appState.cancelRecording()
                }
                .accessibilityHint("Stops microphone startup")
            case .recording:
                hudButton("Cancel recording", systemImage: "xmark", tint: .secondary) {
                    appState.cancelRecording()
                }
                hudButton("Finish recording", systemImage: "checkmark", tint: .white, fill: VhraseTheme.statusRecording) {
                    appState.toggleRecording()
                }
                .accessibilityHint("Stops recording and transcribes the captured audio")
            case .transcribing, .adjusting:
                EmptyView()
            case .completed:
                if !appState.lastTranscript.isEmpty {
                    hudButton("Copy transcript", systemImage: "doc.on.doc") {
                        appState.copyLastTranscript()
                    }
                }
                hudButton("Dismiss", systemImage: "xmark") {
                    appState.dismissWorkflowOutcome()
                }
            case .failed:
                hudButton("Dismiss", systemImage: "xmark") {
                    appState.dismissWorkflowOutcome()
                }
                hudButton("Try again", systemImage: "arrow.clockwise", tint: .white, fill: VhraseTheme.accent) {
                    appState.toggleRecording()
                }
            case .idle:
                EmptyView()
            }
        }
    }

    private func hudButton(
        _ title: String,
        systemImage: String,
        tint: Color = .primary,
        fill: Color = .primary.opacity(0.06),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(fill, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.snappy, reduceMotion: reduceMotion),
            value: appState.status
        )
        .help(title)
        .accessibilityLabel(title)
    }

    private var detailText: String {
        switch appState.status {
        case .preparing:
            "Starting microphone..."
        case .recording:
            presentation.compactLiveTranscriptText
        case .transcribing:
            "Audio captured. \(appState.settings.provider.title) is transcribing it."
        case .adjusting:
            "Applying your writing preferences."
        case .completed:
            appState.lastTranscript.isEmpty ? "Dictation completed." : appState.lastTranscript
        case .failed(let message):
            message
        case .idle:
            ""
        }
    }

    private var detailIsPlaceholder: Bool {
        switch appState.status {
        case .recording:
            appState.liveTranscript.isEmpty
        case .preparing, .transcribing, .adjusting:
            true
        case .idle, .completed, .failed:
            false
        }
    }

    private var showsTranscript: Bool {
        StatusPopupContentPolicy.showsTranscript(
            status: appState.status,
            hasLiveTranscript: !appState.liveTranscript.isEmpty,
            hasFinalTranscript: !appState.lastTranscript.isEmpty
        )
    }

    private var popupWidth: CGFloat {
        showsTranscript ? 400 : 360
    }

    private var popupHeight: CGFloat {
        showsTranscript ? 104 : 54
    }

    private var cornerRadius: CGFloat {
        showsTranscript ? 14 : 12
    }

    private var secondaryStatusText: String {
        switch appState.status {
        case .preparing:
            return "\(appState.settings.provider.title) \(appState.settings.transcriptionMode.title.lowercased())"
        case .recording:
            let target = appState.targetAppLabel.isEmpty ? nil : appState.targetAppLabel
            return [
                "\(appState.settings.provider.title) \(appState.settings.transcriptionMode.title.lowercased())",
                target,
                presentation.elapsedTime,
            ]
            .compactMap(\.self)
            .joined(separator: " · ")
        case .transcribing:
            return "Turning speech into text"
        case .adjusting:
            return "Applying your writing style"
        case .completed:
            return appState.lastDelivery.completionDetail
        case .failed:
            return "Your recording was not delivered"
        case .idle:
            return presentation.fullWorkflowSummary
        }
    }

    private var popupStatusTitle: String {
        appState.isRecording ? presentation.elapsedTime : presentation.displayStatusTitle
    }

    private var popupStatusSystemImage: String {
        appState.status == .completed ? appState.lastDelivery.completionSystemImage : presentation.statusSystemImage
    }

    private var statusColor: Color {
        presentation.statusTint
    }
}

/// Owns the non-activating panel so recorder feedback never steals focus from the target app.
@MainActor
final class RecorderHUDPanelController: NSWindowController {
    private weak var appState: AppState?
    private let hostingView: NSHostingView<StatusPopupView>
    private var delayedHideTask: Task<Void, Never>?
    private var statusObservation: AnyCancellable?
    private var workflowScreen: NSScreen?
    private var previousStatus: AppStatus = .idle

    init(appState: AppState) {
        self.appState = appState
        let hostingView = NSHostingView(rootView: StatusPopupView(appState: appState))
        self.hostingView = hostingView

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 54),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow

        super.init(window: panel)

        statusObservation = Publishers.CombineLatest(
            appState.$status.removeDuplicates(),
            appState.$liveTranscript.removeDuplicates()
        )
            .sink { [weak self] output in
                self?.update(for: output.0)
            }
        update(for: appState.status)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        return nil
    }

    /// Shows active and outcome states, with completed feedback dismissed after a short confirmation.
    func update(for status: AppStatus) {
        delayedHideTask?.cancel()
        delayedHideTask = nil

        let startsNewWorkflow = previousStatus.canStartRecording
            && status != previousStatus
            && status.showsWorkflowPopup
        previousStatus = status

        guard status.showsWorkflowPopup, let panel = window else {
            window?.orderOut(nil)
            workflowScreen = nil
            return
        }

        if startsNewWorkflow || workflowScreen == nil {
            workflowScreen = screenAtPointer()
        }
        resizeAndPosition(panel)
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else {
                return
            }
            self.resizeAndPosition(panel)
        }

        guard status == .completed else {
            return
        }

        delayedHideTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(4.0))
            guard !Task.isCancelled,
                  self?.appState?.status == .completed else {
                return
            }
            panel?.orderOut(nil)
        }
    }

    private func resizeAndPosition(_ panel: NSWindow) {
        let showsTranscript = appState.map {
            StatusPopupContentPolicy.showsTranscript(
                status: $0.status,
                hasLiveTranscript: !$0.liveTranscript.isEmpty,
                hasFinalTranscript: !$0.lastTranscript.isEmpty
            )
        } ?? false
        panel.setContentSize(
            NSSize(
                width: showsTranscript ? 400 : 360,
                height: showsTranscript ? 104 : 54
            )
        )
        position(panel)
    }

    private func position(_ panel: NSWindow) {
        guard let visibleFrame = workflowScreen?.visibleFrame else {
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 24
        )
        panel.setFrameOrigin(origin)
    }

    private func screenAtPointer() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
