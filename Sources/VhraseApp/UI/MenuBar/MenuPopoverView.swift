// Provides Vhrase's capture-first menu-bar controls and routes review or setup work to dedicated windows.

import AppKit
import SwiftUI

struct MenuPopoverView: View {
  @ObservedObject var appState: AppState
  @Environment(\.openWindow) private var openWindow
  @EnvironmentObject private var mainWindow: MainWindowCoordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var presentation: DictationPresentation {
    appState.presentation
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        compactHero
        statusMessagePanel

        Group {
          if showsLiveWorkflow {
            liveTranscriptPanel
              .transition(.move(edge: .top).combined(with: .opacity))
          } else {
            activitySummary
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }

        captureConfiguration

        if let diagnostic = appState.setupDiagnostics.first, diagnostic.severity != .ready {
          setupSummary(diagnostic)
        }
      }
      .padding(14)

      Divider()

      footer
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }
    .frame(width: 368)
    .background(VhraseTheme.canvas)
    .buttonBorderShape(.capsule)
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
      value: showsLiveWorkflow
    )
    .onAppear {
      appState.refreshPermissions()
    }
  }

  /// Mirrors Dictate's mic bar: its fill announces the workflow state and the white disc starts or stops capture.
  private var compactHero: some View {
    let tint = presentation.micBarTint
    return HStack(spacing: 8) {
      RecordHeroButton(
        presentation: presentation,
        meter: appState.recordingMeter,
        style: .compact,
        action: handleRecordButton
      )

      VStack(alignment: .leading, spacing: 1) {
        Text(presentation.displayStatusTitle)
          .font(VhraseFont.title)
        Text(presentation.compactWorkflowSummary)
          .font(VhraseFont.micro)
          .opacity(0.85)
          .lineLimit(1)
      }

      Spacer()
    }
    .foregroundStyle(tint == nil ? Color.primary : Color.white)
    .padding(4)
    .background(
      tint ?? VhraseTheme.card,
      in: RoundedRectangle(cornerRadius: VhraseTheme.sheetCornerRadius, style: .continuous)
    )
    .overlay {
      if tint == nil {
        RoundedRectangle(cornerRadius: VhraseTheme.sheetCornerRadius, style: .continuous)
          .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
      }
    }
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
      value: appState.status
    )
  }

  @ViewBuilder
  private var statusMessagePanel: some View {
    if appState.status == .completed {
      NoticeCard(
        appState.lastCompletion.completionDetail,
        systemImage: appState.lastCompletion.completionSystemImage,
        color: presentation.statusTint,
        actionTitle: completedInsertionPermissionActionTitle,
        action: { appState.handlePermissionAction(.accessibility) }
      )
    } else if let message = presentation.statusMessage {
      NoticeCard(
        message,
        systemImage: presentation.statusMessageIcon,
        color: statusMessageColor
      )
    }
  }

  private var liveTranscriptPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(presentation.displayStatusTitle, systemImage: menuStatusSystemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(presentation.statusTint)

        Spacer()

        if appState.isRecording {
          RecordingElapsedTime(meter: appState.recordingMeter)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        if !appState.targetAppLabel.isEmpty {
          Text("→ \(appState.targetAppLabel)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      if appState.isRecording {
        RecordingWaveformView(meter: appState.recordingMeter, barCount: 16, height: 28)
      }

      Text(liveTranscriptText)
        .font(VhraseFont.transcriptBody)
        .foregroundStyle(appState.liveTranscript.isEmpty ? .secondary : .primary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
        .textSelection(.enabled)
    }
    .padding(10)
    .surface()
  }

  private var activitySummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Activity")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Spacer()

        Button("History") {
          openMainWindow(.history)
        }
        .buttonStyle(AccentLinkButtonStyle())
        .accessibilityHint("Opens all saved transcripts")
      }

      if !appState.lastTranscript.isEmpty {
        lastTranscriptRow
      }

      HStack(spacing: 0) {
        menuMetric("Today", value: "\(appState.todayActivity().dictations)")

        Divider()
          .frame(height: 28)

        menuMetric("Saved", value: "\(appState.history.count)")

        Divider()
          .frame(height: 28)

        VStack(alignment: .leading, spacing: 1) {
          Text(appState.savesTranscriptHistory ? "On" : "Off")
            .font(VhraseFont.title)
          Text("Saving")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(10)
      .surface()
    }
  }

  private var lastTranscriptRow: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(appState.lastTranscript)
        .font(VhraseFont.transcriptBody)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)

      Button {
        appState.copyLastTranscript()
      } label: {
        Image(systemName: "doc.on.doc")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Copy last transcript")
      .accessibilityLabel("Copy last transcript")
    }
    .padding(10)
    .surface()
  }

  private func menuMetric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value)
        .font(VhraseFont.title)
        .contentTransition(.numericText())
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var captureConfiguration: some View {
    HStack(spacing: 8) {
      Label("Input", systemImage: "slider.horizontal.2.square")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .fixedSize()

      Spacer()

      ProviderPicker(selection: appState.settingsBinding(\.provider))
        .fixedSize()
        .accessibilityLabel("Transcription provider")

      Picker("Mode", selection: appState.settingsBinding(\.transcriptionMode)) {
        ForEach(TranscriptionMode.allCases) { mode in
          Text(mode.title(for: appState.settings.provider)).tag(mode)
            .disabled(!appState.settings.provider.availableModes.contains(mode))
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
      .accessibilityLabel("Transcription mode")
    }
    .padding(10)
    .surface()
    .disabled(presentation.workflowControlsAreDisabled)
  }

  private func setupSummary(_ diagnostic: SetupDiagnostic) -> some View {
    Button {
      openMainWindow(.system)
    } label: {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: diagnostic.systemImage)
          .foregroundStyle(VhraseTheme.diagnosticColor(diagnostic.severity))
          .frame(width: 18)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
          Text(diagnostic.title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
          Text(diagnostic.detail)
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
      .padding(10)
      .background(
        VhraseTheme.diagnosticColor(diagnostic.severity).opacity(0.1),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Opens System in the main Vhrase window")
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Button {
        openMainWindow()
      } label: {
        Label("Dictate", systemImage: "waveform")
      }
      .buttonStyle(.borderless)

      Button {
        openMainWindow(.system)
      } label: {
        Label("System", systemImage: "wrench.and.screwdriver")
      }
      .buttonStyle(.borderless)
      .help("System")
      .accessibilityLabel("System")

      Spacer()

      Divider()
        .frame(height: 16)

      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Image(systemName: "power")
      }
      .buttonStyle(.borderless)
      .help("Quit Vhrase")
      .accessibilityLabel("Quit Vhrase")
    }
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

  private var menuStatusSystemImage: String {
    appState.status == .completed
      ? appState.lastCompletion.completionSystemImage : presentation.statusSystemImage
  }

  private var completedInsertionPermissionActionTitle: String? {
    guard appState.status == .completed, appState.lastCompletion == .transcript(.copied) else {
      return nil
    }
    return presentation.insertionPermissionActionTitle
  }

  private var statusMessageColor: Color {
    if case .failed = appState.status {
      return VhraseTheme.statusFailure
    }
    return VhraseTheme.statusWarning
  }

  private func handleRecordButton() {
    switch presentation.recordAction {
    case .toggleRecording:
      appState.toggleRecording()
    case .cancelRecording:
      appState.cancelRecording()
    case .openSetup:
      openMainWindow(.system)
    case .disabled:
      break
    }
  }

  private func openMainWindow(_ tab: MainWindowTab = .dictate) {
    mainWindow.open(tab, using: openWindow)
  }

}
