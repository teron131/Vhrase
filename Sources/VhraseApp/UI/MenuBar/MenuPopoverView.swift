// Provides Vhrase's capture-first menu-bar controls and routes review or setup work to dedicated windows.

import AppKit
import SwiftUI

struct MenuPopoverView: View {
  @ObservedObject var appState: AppState
  @Environment(\.openWindow) private var openWindow
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

        if primarySetupDiagnostic.severity != .ready {
          setupSummary
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
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
      value: showsLiveWorkflow
    )
    .onAppear {
      appState.refreshPermissions()
    }
  }

  private var compactHero: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Vhrase")
          .font(VhraseFont.micro)
          .foregroundStyle(VhraseTheme.accent)
        Text(presentation.displayStatusTitle)
          .font(VhraseFont.title)
        Text(presentation.compactWorkflowSummary)
          .font(VhraseFont.micro)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      KeyCap(text: appState.settings.hotkeyDisplay)

      RecordHeroButton(
        presentation: presentation,
        recordingLevel: appState.recordingLevel,
        style: .compact,
        action: handleRecordButton
      )
    }
    .padding(12)
    .background(VhraseTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
    }
    .shadow(color: presentation.statusTint.opacity(0.12), radius: 16, y: 6)
  }

  @ViewBuilder
  private var statusMessagePanel: some View {
    if appState.status == .completed {
      NoticeCard(
        appState.lastDelivery.completionDetail,
        systemImage: appState.lastDelivery.completionSystemImage,
        color: presentation.statusTint,
        actionTitle: completedInsertionPermissionActionTitle,
        action: handleInsertionPermissionAction
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
          Text(presentation.elapsedTime)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }

        if !appState.targetAppLabel.isEmpty {
          Text("→ \(appState.targetAppLabel)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      if appState.isRecording {
        WaveformView(
          level: appState.recordingLevel,
          barCount: 16,
          height: 28
        )
      }

      Text(liveTranscriptText)
        .font(.callout)
        .foregroundStyle(appState.liveTranscript.isEmpty ? .secondary : .primary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
        .textSelection(.enabled)
    }
    .padding(10)
    .insetField(cornerRadius: 10)
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
        menuMetric("Today", value: "\(appState.transcriptsTodayCount)")

        Divider()
          .frame(height: 28)

        menuMetric("Saved", value: "\(appState.history.count)")

        Divider()
          .frame(height: 28)

        VStack(alignment: .leading, spacing: 1) {
          Text(appState.savesTranscriptHistory ? "On" : "Off")
            .font(.callout.weight(.semibold))
          Text("Saving")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(10)
      .insetField(cornerRadius: 9)
    }
  }

  private var lastTranscriptRow: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(appState.lastTranscript)
        .font(.caption)
        .foregroundStyle(.secondary)
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
    .insetField(cornerRadius: 9)
  }

  private func menuMetric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value)
        .font(.callout.weight(.semibold))
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
        ForEach(appState.settings.provider.availableModes) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
      .accessibilityLabel("Transcription mode")
    }
    .padding(10)
    .insetField(cornerRadius: 9)
    .disabled(presentation.workflowControlsAreDisabled)
  }

  private var setupSummary: some View {
    let diagnostic = primarySetupDiagnostic
    return Button {
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
      ? appState.lastDelivery.completionSystemImage : presentation.statusSystemImage
  }

  private var primarySetupDiagnostic: SetupDiagnostic {
    appState.setupDiagnostics.first
      ?? SetupDiagnostic(
        id: "ready",
        title: "Ready",
        detail: "Vhrase is ready to record.",
        systemImage: "checkmark.circle.fill",
        severity: .ready
      )
  }

  private var completedInsertionPermissionActionTitle: String? {
    guard appState.status == .completed,
      appState.lastDelivery == .copied
    else {
      return nil
    }
    return presentation.insertionPermissionActionTitle
  }

  private func handleInsertionPermissionAction() {
    guard let snapshot = presentation.permissionSnapshot(.accessibility) else {
      return
    }
    appState.handlePermissionAction(snapshot)
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
    UserDefaults.standard.set(tab.rawValue, forKey: "mainWindow.selectedTab")
    openWindow(id: "main")
    DispatchQueue.main.async {
      NSApplication.shared.activate()
    }
  }

}
