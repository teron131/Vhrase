// Owns the recording workspace, transcript comparison, and activity summary; session selection survives navigation.

import AppKit
import SwiftUI

struct DictationView: View {
  @ObservedObject var appState: AppState
  @Binding var selectedTab: MainWindowTab
  @Binding var activityRange: ActivityRange
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    dictationTab.mainWindowEvents(appState: appState)
  }

  private var dictationTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        pageHeader(
          "Dictate",
          description:
            "Speak naturally, review the result, and keep writing without changing apps.",
          systemImage: MainWindowTab.dictate.systemImage
        )

        HStack(alignment: .top, spacing: 24) {
          recordPanel
            .frame(width: 310)
            .hoverLift()

          transcriptCard
            .frame(maxWidth: .infinity)
            .hoverLift()
        }
        // Size the row to its taller card, then let both surfaces fill that shared height.
        .fixedSize(horizontal: false, vertical: true)
        quickActionsCard
      }
      .frame(maxWidth: 1040, alignment: .topLeading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .background(alignment: .topLeading) {
      Circle()
        .fill(VhraseTheme.accent.opacity(0.065))
        .frame(width: 420, height: 420)
        .blur(radius: 80)
        .offset(x: -150, y: -210)
        .accessibilityHidden(true)
    }
  }

  private var recordPanel: some View {
    VStack(spacing: 16) {
      ProviderPicker(selection: appState.settingsBinding(\.provider))
        .disabled(presentation.workflowControlsAreDisabled)

      RecordHeroButton(
        presentation: presentation,
        recordingLevel: appState.recordingLevel,
        style: .hero,
        action: handleRecordButton
      )

      Text(presentation.displayStatusTitle)
        .font(VhraseFont.pageTitle)
        .tracking(-0.5)
        .multilineTextAlignment(.center)
        .contentTransition(.interpolate)

      if appState.isRecording {
        Text(presentation.elapsedTime)
          .font(VhraseFont.timer)
          .contentTransition(.numericText())
      }

      Text(statusDetail)
        .font(VhraseFont.caption)
        .foregroundStyle(VhraseTheme.inkSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      if appState.isRecording {
        WaveformView(history: appState.recordingWaveformHistory)
          .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }

      HStack(spacing: 12) {
        Text(presentation.fullWorkflowSummary)
        KeyCap(text: appState.settings.hotkeyDisplay)
      }
      .font(VhraseFont.micro)
      .foregroundStyle(VhraseTheme.inkSecondary)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .operationalSurface()
    .shadow(
      color: presentation.statusTint.opacity(presentation.coreRecordingReady ? 0.16 : 0),
      radius: 24, y: 8
    )
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
      value: appState.status
    )
  }

  private var transcriptCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(transcriptWorkspaceTitle)
            .font(VhraseFont.title)
          Text(transcriptWorkspaceSubtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if showsLiveCapture, !appState.targetAppLabel.isEmpty {
          Label(appState.targetAppLabel, systemImage: "arrow.right.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if transcriptWorkspaceShowsCopyAction {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcriptWorkspaceCopyText, forType: .string)
          } label: {
            Label(transcriptWorkspaceCopyTitle, systemImage: "doc.on.doc")
          }
          .buttonStyle(.bordered)
          .disabled(transcriptWorkspaceCopyText.isEmpty)
          .accessibilityHint("Copies the displayed transcript to the clipboard")
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        Text(transcriptWorkspaceText)
          .font(VhraseFont.transcript)
          .foregroundStyle(transcriptWorkspaceIsPlaceholder ? .secondary : .primary)
          .frame(maxWidth: .infinity, minHeight: 142, maxHeight: .infinity, alignment: .topLeading)
          .textSelection(.enabled)
          .contentTransition(.interpolate)
          .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.settle, reduceMotion: reduceMotion),
            value: transcriptWorkspaceText
          )
      }
      .padding(16)
      .insetField()

      if !showsLiveCapture, !appState.lastRecognizedTranscript.isEmpty {
        HStack {
          if let seconds = appState.lastTranscriptionSeconds {
            Label(String(format: "Transcription wait: %.2f s", seconds), systemImage: "stopwatch")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .help(
                "Time from stopping capture to the completed provider transcript, excluding later LLM cleanup."
              )
          }
          Spacer()
        }
        DisclosureGroup("Before Vhrase cleanup") {
          VStack(alignment: .leading, spacing: 8) {
            Text(appState.lastRecognizedTranscript)
              .font(VhraseFont.transcript)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy original transcription") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(appState.lastRecognizedTranscript, forType: .string)
            }
            .buttonStyle(AccentLinkButtonStyle())
          }
          .padding(.top, 8)
        }
        .font(.callout)
      }

      if !appState.lastAdjustmentWarning.isEmpty {
        NoticeCard(
          appState.lastAdjustmentWarning,
          systemImage: "exclamationmark.triangle",
          color: VhraseTheme.statusWarning,
          actionTitle: presentation.insertionPermissionActionTitle,
          action: handleInsertionPermissionAction
        )
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .contentSection()
  }

  private var quickActionsCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        sectionHeader(
          "Activity", description: "Local totals since tracking began. Works with history off.")
        Spacer()
        Button("View history") {
          selectedTab = .history
        }
        .buttonStyle(AccentLinkButtonStyle())
        .disabled(appState.history.isEmpty)
      }

      Picker("Activity period", selection: $activityRange) {
        ForEach(ActivityRange.allCases, id: \.self) { range in
          Text(range.rawValue).tag(range)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 360)

      TimelineView(.periodic(from: .now, by: 60)) { context in
        let totals = activityRange.totals(days: appState.activityDays, now: context.date)
        HStack(spacing: 18) {
          activityMetric("Dictations", value: totals.dictations.formatted(), detail: "completed")
          Divider().frame(height: 48)
          activityMetric("Words", value: totals.words.formatted(), detail: "dictated")
          Divider().frame(height: 48)
          activityMetric(
            "Est. time saved", value: activityTimeSaved(totals.savedSeconds),
            detail: "vs. typing at 55 WPM"
          )
          .help(
            "Compared with typing at 55 words per minute, subtracting recording and all processing time. Language-aware word counts and time saved are estimates."
          )
          Divider().frame(height: 48)
          activityMetric(
            "Est. cost", value: activityCost(totals.estimatedCostUSD),
            detail: "USD · transcription only"
          )
          .help(
            "List-price estimate for completed dictations since tracking began. Excludes cleanup, failed requests, subscriptions, and free-tier credits. Gemini uses an approximate per-minute rate."
          )
        }
      }

      Divider()

      TimelineView(.periodic(from: .now, by: 60)) { context in
        DictationActivityChart(days: appState.activityDays, now: context.date, range: activityRange)
      }

      Divider()

      HStack(spacing: 16) {
        Button {
          appState.runDemoDictation()
        } label: {
          Label("Run demo", systemImage: "play.circle")
        }
        .disabled(!appState.status.canStartRecording)

        Spacer()

        Button {
          selectedTab = .capture
        } label: {
          Label("Transcription settings", systemImage: "mic.and.signal.meter")
        }

        Button {
          selectedTab = .system
          appState.refreshPermissions()
        } label: {
          Label("Check readiness", systemImage: "checkmark.circle")
        }
      }
      .buttonStyle(AccentLinkButtonStyle())
    }
    .contentSection()
  }

  private func activityTimeSaved(_ seconds: Double) -> String {
    let wholeSeconds = Int(seconds)
    if wholeSeconds < 60 { return "\(wholeSeconds)s" }
    if wholeSeconds < 3_600 { return "\(wholeSeconds / 60)m \(wholeSeconds % 60)s" }
    return "\(wholeSeconds / 3_600)h \(wholeSeconds % 3_600 / 60)m"
  }

  private func activityCost(_ dollars: Double) -> String {
    if dollars > 0 && dollars < 0.01 { return "<$0.01" }
    return dollars.formatted(.currency(code: "USD"))
  }

  private var transcriptWorkspaceTitle: String {
    if hasInterruptedLiveTranscript {
      return "Interrupted transcript"
    }
    return showsLiveCapture ? "Live transcript" : "Latest transcript"
  }

  private var transcriptWorkspaceSubtitle: String {
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

  private var transcriptWorkspaceText: String {
    if hasInterruptedLiveTranscript {
      return appState.liveTranscript
    }
    return switch appState.status {
    case .preparing:
      "Starting microphone…"
    case .recording:
      presentation.fullLiveTranscriptText
    case .transcribing:
      appState.liveTranscript.isEmpty
        ? "Audio captured. Waiting for \(appState.settings.provider.title) to return the transcript…"
        : appState.liveTranscript
    case .adjusting:
      appState.liveTranscript.isEmpty
        ? "Transcript received. Applying your writing preferences…"
        : appState.liveTranscript
    case .idle, .completed, .failed:
      appState.lastTranscript.isEmpty
        ? "Your next transcript will appear here." : appState.lastTranscript
    }
  }

  private var transcriptWorkspaceIsPlaceholder: Bool {
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

  private var transcriptWorkspaceCopyText: String {
    hasInterruptedLiveTranscript ? appState.liveTranscript : appState.lastTranscript
  }

  private var transcriptWorkspaceCopyTitle: String {
    hasInterruptedLiveTranscript ? "Copy partial" : "Copy"
  }

  private var transcriptWorkspaceShowsCopyAction: Bool {
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

  private var statusDetail: String {
    switch appState.status {
    case .idle:
      let presentation = self.presentation
      if !presentation.selectedProviderHasKey {
        return "Add the selected provider key before recording."
      }
      if !presentation.permissionIsReady(.microphone) {
        return "Grant Microphone access before recording."
      }
      if let transcriptionConfigurationIssue = presentation.transcriptionConfigurationIssue {
        return transcriptionConfigurationIssue
      }
      return "Ready for \(presentation.fullWorkflowSummary)."
    case .preparing:
      return "Starting the microphone and preparing \(appState.settings.provider.title)."
    case .recording:
      return
        "Listening. Release after a hold, or tap \(appState.settings.hotkeyDisplay) again when you are done."
    case .transcribing:
      return "Transcribing with \(appState.settings.provider.title)."
    case .adjusting:
      return "Applying writing preferences."
    case .completed:
      return appState.lastCompletion.completionDetail
    case .failed(let message):
      return message
    }
  }

  private var showsLiveCapture: Bool {
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

  private func handleRecordButton() {
    switch presentation.recordAction {
    case .toggleRecording:
      appState.toggleRecording()
    case .cancelRecording:
      appState.cancelRecording()
    case .openSetup:
      selectedTab = .system
    case .disabled:
      break
    }
  }

  /// Requests or opens the macOS permission required to insert finalized transcripts into other apps.
  private func handleInsertionPermissionAction() {
    guard let snapshot = presentation.permissionSnapshot(.accessibility) else {
      return
    }
    appState.handlePermissionAction(snapshot)
  }
}
