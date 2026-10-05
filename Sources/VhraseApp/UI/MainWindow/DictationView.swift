// Owns the recording workspace, transcript comparison, and activity summary; session selection survives navigation.

import AppKit
import SwiftUI

struct DictationView: View {
  @ObservedObject var appState: AppState
  @Binding var selectedTab: MainWindowTab
  @Binding var activityRange: ActivityRange
  @State private var activityMetric = ActivityMetric.words
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    dictationTab.mainWindowEvents(appState: appState)
  }

  private var dictationTab: some View {
    mainWindowPage(spacing: 24) {
      pageHeader(
        "Dictate",
        description: "Speak naturally, review the result, and keep writing without changing apps."
      ) {
        Button {
          appState.runDemoDictation()
        } label: {
          Label("Run demo", systemImage: "play.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!appState.status.canStartRecording)
        .help(
          "Runs cleanup, history, and clipboard delivery on sample text without calling a provider or pasting."
        )
      }

      micBar
      speechBubble
      activitySection
    }
  }

  /// Puts the record control, live signal, and provider on one bar whose fill announces the workflow state.
  private var micBar: some View {
    let tint = presentation.micBarTint
    return HStack(alignment: .center, spacing: 14) {
      RecordHeroButton(
        presentation: presentation,
        recordingLevel: appState.recordingLevel,
        style: .hero,
        action: handleRecordButton
      )

      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(presentation.displayStatusTitle)
            .font(VhraseFont.statusTitle)
            .contentTransition(.interpolate)
          if appState.isRecording {
            Text(presentation.elapsedTime)
              .font(VhraseFont.timer)
              .opacity(0.85)
              .contentTransition(.numericText())
          }
        }
        Text(statusDetail)
          .font(VhraseFont.caption)
          .opacity(0.85)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .layoutPriority(1)

      // Rests as quiet dots and becomes the live microphone level while recording.
      WaveformView(
        history: appState.isRecording ? appState.recordingWaveformHistory : [],
        barCount: 32,
        tint: tint == nil ? VhraseTheme.inkSecondary : .white,
        height: 30
      )
      .frame(minWidth: 80, maxWidth: 250)
      .frame(maxWidth: .infinity)

      providerChip(onTint: tint != nil)
    }
    .foregroundStyle(tint == nil ? Color.primary : Color.white)
    .padding(.leading, 10)
    .padding(.trailing, 14)
    .padding(.vertical, 10)
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

  /// Names the provider and mode on the bar and switches either without leaving Dictate.
  private func providerChip(onTint: Bool) -> some View {
    Menu {
      Picker("Provider", selection: appState.settingsBinding(\.provider)) {
        ForEach(STTProvider.allCases, id: \.self) { provider in
          Text(provider.title).tag(provider)
        }
      }
      .pickerStyle(.inline)

      Picker("Mode", selection: appState.settingsBinding(\.transcriptionMode)) {
        ForEach(TranscriptionMode.allCases, id: \.self) { mode in
          Text(mode.title).tag(mode)
            .disabled(!appState.settings.provider.availableModes.contains(mode))
        }
      }
      .pickerStyle(.inline)
    } label: {
      Text("\(appState.settings.provider.title) · \(appState.settings.transcriptionMode.title)")
        .font(VhraseFont.pill)
    }
    .menuStyle(.borderlessButton)
    .tint(onTint ? .white : VhraseTheme.accent)
    .fixedSize()
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Capsule().fill(onTint ? Color.white.opacity(0.22) : VhraseTheme.field))
    .disabled(presentation.workflowControlsAreDisabled)
    .accessibilityLabel("Transcription provider and mode")
  }

  /// The parrot repeats what you said: the transcript sits in a speech bubble pointing back at the mark.
  private var speechBubble: some View {
    let bubble = UnevenRoundedRectangle(
      topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 22,
      topTrailingRadius: 22, style: .continuous)
    return HStack(alignment: .bottom, spacing: 10) {
      ParrotMark()
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)

      transcriptWorkspace
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(VhraseTheme.card, in: bubble)
        .overlay { bubble.strokeBorder(VhraseTheme.hairline, lineWidth: 1) }
    }
  }

  private var transcriptWorkspace: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(transcriptWorkspaceTitle)
          .font(VhraseFont.headline)
        Text(transcriptWorkspaceSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 8)
        if showsLiveCapture, !appState.targetAppLabel.isEmpty {
          Label(appState.targetAppLabel, systemImage: "arrow.right.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if !showsLiveCapture, !appState.history.isEmpty {
          Button("View history") {
            selectedTab = .history
          }
          .buttonStyle(AccentLinkButtonStyle())
          .font(.callout)
        }
        if transcriptWorkspaceShowsCopyAction {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcriptWorkspaceCopyText, forType: .string)
          } label: {
            Label(transcriptWorkspaceCopyTitle, systemImage: "doc.on.doc")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(transcriptWorkspaceCopyText.isEmpty)
          .accessibilityHint("Copies the displayed transcript to the clipboard")
        }
      }

      Text(transcriptWorkspaceText)
        .font(VhraseFont.transcript)
        .lineSpacing(5)
        .foregroundStyle(transcriptWorkspaceIsPlaceholder ? .secondary : .primary)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .textSelection(.enabled)
        .contentTransition(.interpolate)
        .animation(
          VhraseMotion.respectingReduceMotion(VhraseMotion.settle, reduceMotion: reduceMotion),
          value: transcriptWorkspaceText
        )

      if !showsLiveCapture, !appState.lastRecognizedTranscript.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          if let seconds = appState.lastTranscriptionSeconds {
            Label(String(format: "Transcription wait: %.2f s", seconds), systemImage: "stopwatch")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .help(
                "Time from stopping capture to the completed provider transcript, excluding later LLM cleanup."
              )
          }
          DisclosureGroup("Before Vhrase cleanup") {
            VStack(alignment: .leading, spacing: 8) {
              Text(appState.lastRecognizedTranscript)
                .font(VhraseFont.transcriptBody)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
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
        .padding(.top, 12)
        .overlay(alignment: .top) {
          Rectangle()
            .fill(VhraseTheme.hairline)
            .frame(height: 1)
        }
      }

      if !appState.lastAdjustmentWarning.isEmpty {
        NoticeCard(
          appState.lastAdjustmentWarning,
          systemImage: "exclamationmark.triangle",
          color: VhraseTheme.statusWarning,
          actionTitle: presentation.insertionPermissionActionTitle,
          action: { appState.handlePermissionAction(.accessibility) }
        )
      }
    }
  }

  private var activitySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .bottom, spacing: 16) {
        sectionHeader(
          "Activity", description: "Local totals since tracking began. Works with history off.")
        Spacer()
        PillPicker(
          title: "Activity period", selection: $activityRange, options: ActivityRange.allCases,
          label: \.rawValue)
      }

      TimelineView(.periodic(from: .now, by: 60)) { context in
        DictationActivityChart(
          days: appState.activityDays, now: context.date, range: activityRange,
          metric: $activityMetric)
      }
    }
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
      return appState.settings.hotkeyPreset == .disabled
        ? "Click the button to start talking."
        : "Hold \(appState.settings.hotkeyDisplay) and talk, or tap it to start and stop."
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
}
