// Implements the sidebar destinations and complete configuration workflows for Vhrase's main window.

import AVFoundation
import AppKit
import SwiftUI

extension MainWindowView {
  var sidebar: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            ParrotMark()
              .frame(width: 22, height: 22)
              .accessibilityHidden(true)
            Text("Vhrase")
              .font(VhraseFont.title)
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 12)

          ForEach(MainWindowTab.allCases) { tab in
            Button {
              if tab == .capture, selectedTab == .capture {
                restartListeningPreview()
              }
              withAnimation(
                VhraseMotion.respectingReduceMotion(
                  VhraseMotion.stateSpring, reduceMotion: reduceMotion)
              ) {
                selectedTab = tab
              }
            } label: {
              HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                  .font(.callout)
                  .foregroundStyle(
                    selectedTab == tab ? VhraseTheme.accent : VhraseTheme.inkSecondary
                  )
                  .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                  Text(tab.title)
                    .font(.callout.weight(selectedTab == tab ? .semibold : .medium))
                    .lineLimit(1)
                  Text(tab.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if tab == .dictate, appState.isRecording {
                  Spacer(minLength: 4)
                  Circle()
                    .fill(VhraseTheme.statusRecording)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 7)
              .padding(.horizontal, 8)
              .background {
                if selectedTab == tab {
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(VhraseTheme.accentSubtle)
                    .matchedGeometryEffect(id: "navigation-selection", in: navigationSelection)
                } else if hoveredTab == tab {
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
              if isHovered {
                hoveredTab = tab
              } else if hoveredTab == tab {
                hoveredTab = nil
              }
            }
            .animation(
              VhraseMotion.respectingReduceMotion(VhraseMotion.settle, reduceMotion: reduceMotion),
              value: hoveredTab
            )
            .accessibilityValue(selectedTab == tab ? "Selected" : "")
            .accessibilityHint(tab.detail)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      sidebarFooter
    }
    .background(.bar)
  }

  var sidebarFooter: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()

      Button {
        selectedTab = .system
        appState.refreshPermissions()
      } label: {
        HStack(spacing: 8) {
          Circle()
            .fill(sidebarReadinessColor)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
          Text(sidebarReadinessTitle)
            .fontWeight(.medium)
            .lineLimit(1)
          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens access and readiness settings")

      HStack {
        Text("Shortcut")
          .foregroundStyle(.secondary)
        Spacer()
        KeyCap(text: appState.settings.hotkeyDisplay)
      }

    }
    .font(.callout)
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
    .background(.bar)
  }

  var actionNoticeBanner: some View {
    HStack(spacing: 9) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(VhraseTheme.accent)
        .accessibilityHidden(true)

      Text(appState.customizationNotice)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)

      Button {
        appState.dismissCustomizationNotice(appState.customizationNotice)
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .help("Dismiss")
      .accessibilityLabel("Dismiss notification")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
    .overlay(alignment: .bottom) {
      Divider()
    }
    .accessibilityElement(children: .contain)
  }

  var dictationTab: some View {
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

  var recordPanel: some View {
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
        WaveformView(level: appState.recordingLevel)
          .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }

      HStack(spacing: 12) {
        Text(presentation.fullWorkflowSummary)
        KeyCap(text: appState.settings.hotkeyDisplay)
      }
      .font(VhraseFont.micro)
      .foregroundStyle(VhraseTheme.inkSecondary)
    }
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

  var transcriptCard: some View {
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
          .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
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
    .contentSection()
  }

  var quickActionsCard: some View {
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
          Label("Capture settings", systemImage: "mic.and.signal.meter")
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

  var captureTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        pageHeader(
          "Capture",
          description: "Choose how Vhrase listens and which shortcut follows you across apps.",
          systemImage: MainWindowTab.capture.systemImage
        )

        workflowEditor(
          "Capture workflow",
          description: "Select a stage to configure it. Each setting lives in one place.",
          nodes: capturePipelineNodes,
          selection: Binding(
            get: { selectedCapturePipelineStage },
            set: { stage in
              if stage == .listen {
                restartListeningPreview()
              }
              selectedCapturePipelineStage = stage
            }
          )
        ) {
          captureWorkflowStageEditor
        }
      }
      .frame(maxWidth: 1040, alignment: .topLeading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .disabled(presentation.workflowControlsAreDisabled)
  }

  /// Repeated navigation to Listen reacquires capture without interrupting an active dictation.
  private func restartListeningPreview() {
    guard selectedCapturePipelineStage == .listen, appState.status.canStartRecording else { return }
    NSApp.activate()
    appState.audioInputPreview.restart(settings: appState.settings)
  }

  var outputTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .center, spacing: 16) {
          pageHeader(
            "Output",
            description: "Shape the transcript after recognition, then choose what to retain.",
            systemImage: MainWindowTab.output.systemImage
          )
          Spacer()
          customizationActions
        }

        workflowEditor(
          "Output workflow",
          description:
            "Corrections run first, LLM enhancement is optional, and delivery completes the path.",
          nodes: outputPipelineNodes,
          selection: $selectedOutputPipelineStage
        ) {
          outputWorkflowStageEditor
        }
      }
      .frame(maxWidth: 1040, alignment: .topLeading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .disabled(presentation.workflowControlsAreDisabled)
  }

  var transcriptionStageSettings: some View {
    VStack(alignment: .leading, spacing: 14) {
      workflowStageHeader(
        "Transcribe",
        description: "Choose the speech service and tune how it recognizes your words.",
        systemImage: "waveform"
      )

      LabeledContent("Provider") {
        ProviderPicker(selection: appState.settingsBinding(\.provider), style: .segmented)
          .fixedSize()
      }

      labeledPicker("Mode") {
        Picker("Mode", selection: appState.settingsBinding(\.transcriptionMode)) {
          ForEach(appState.settings.provider.availableModes) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      Text(appState.settings.provider.detail)
        .font(.callout)
        .foregroundStyle(.secondary)
      if appState.settings.provider == .gemini {
        Text(
          "Audio is sent directly to Google after you stop. Interaction storage is disabled. Live Gemini transcription is not enabled in this version."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 12) {
        Label(
          "\(appState.settings.provider.title) options",
          systemImage: "slider.horizontal.3"
        )
        .font(.subheadline.weight(.medium))

        providerSpecificControls
      }

      Divider()

      editorTile(
        "Shared vocabulary",
        systemImage: "tag",
        text: appState.settingsBinding(\.keyterms),
        height: 126,
        instruction:
          "One word or phrase per line. The same list is used by every provider; duplicates are ignored.",
        placeholder: "Vercel\nbackpropagation\nMonte Carlo"
      )

      HStack {
        Text("\(appState.settings.keytermList.count) unique terms")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        Button("Add developer vocabulary") {
          appState.updateSettings { settings in
            let terms = [
              "Codex", "ChatGPT", "Anthropic", "Claude", "Vercel", "refactor", "schema", "JSON",
              "docstring", "backpropagation", "Monte Carlo",
            ]
            let keyterms = settings.keytermList
            let existing = Set(keyterms.map { $0.lowercased() })
            let additions = terms.filter { !existing.contains($0.lowercased()) }
            settings.keyterms = (keyterms + additions).joined(separator: "\n")
          }
        }
        .buttonStyle(AccentLinkButtonStyle())
        .help("Adds common developer terms without replacing your vocabulary")
      }

      Text(keytermGuidance)
        .font(.caption)
        .foregroundStyle(
          appState.transcriptionConfigurationIssue == nil ? Color.secondary : Color.red)
    }
    .toggleStyle(.switch)
  }

  @ViewBuilder
  private var providerSpecificControls: some View {
    switch appState.settings.provider {
    case .gemini:
      settingsToggle(
        "Smart transcription",
        detail:
          "Remove fillers, resolve spoken corrections, and format paragraphs and lists. Turn off when you need closer preservation of the spoken words.",
        isOn: appState.settingsBinding(\.geminiSmartTranscription))
      if appState.settings.geminiSmartTranscription, appState.settings.adjustWithLLM {
        HStack(alignment: .top, spacing: 12) {
          Text("LLM enhancement is also on. It will rewrite the Smart transcript a second time.")
            .font(.caption)
            .foregroundStyle(VhraseTheme.statusWarning)
          Button("Use Smart only") {
            appState.updateSettings { $0.adjustWithLLM = false }
          }
          .buttonStyle(.bordered)
        }
      }
    case .xai:
      settingsToggle(
        "Keep filler words", detail: "Include “um” and “uh”. Off removes them during recognition.",
        isOn: appState.settingsBinding(\.includeFillerWords))
      settingsToggle(
        "Format numbers and currency",
        detail:
          "Uses the language in Listen settings. For example, “one hundred dollars” becomes “$100”.",
        isOn: appState.settingsBinding(\.xaiFormatText))

      if appState.settings.transcriptionMode == .realtime {
        LabeledContent("Speech detection threshold") {
          HStack {
            Slider(value: appState.settingsBinding(\.xaiVADThreshold), in: 0...1, step: 0.01)
            Text(appState.settings.xaiVADThreshold, format: .number.precision(.fractionLength(2)))
              .font(.callout.monospacedDigit())
          }.frame(maxWidth: 280)
        }
        Text(
          "Lower values can help with quiet speech but may transcribe background noise. Zero disables the gate; default is 0.08."
        )
        .font(.caption).foregroundStyle(.secondary)
        Stepper(
          "Endpointing: \(appState.settings.xaiRealtimeEndpointing) ms",
          value: appState.settingsBinding(\.xaiRealtimeEndpointing),
          in: 0...5000,
          step: 100
        )

        settingsToggle(
          "Smart Turn",
          detail:
            "Wait for a complete thought before ending a turn. This controls timing, not text cleanup.",
          isOn: appState.settingsBinding(\.xaiSmartTurnEnabled))

        if appState.settings.xaiSmartTurnEnabled {
          LabeledContent("Smart Turn threshold") {
            HStack(spacing: 10) {
              Slider(
                value: appState.settingsBinding(\.xaiSmartTurnThreshold),
                in: 0...1,
                step: 0.05
              )
              Text(
                appState.settings.xaiSmartTurnThreshold,
                format: .number.precision(.fractionLength(2))
              )
              .font(.callout.monospacedDigit())
              .frame(width: 36, alignment: .trailing)
            }
            .frame(maxWidth: 280)
          }
          Stepper(
            "Smart Turn timeout: \(appState.settings.xaiSmartTurnTimeout) ms",
            value: appState.settingsBinding(\.xaiSmartTurnTimeout),
            in: 1...5000,
            step: 100
          )
        }
      }
    case .elevenLabs:
      LabeledContent("Model") {
        Text(
          appState.settings.transcriptionMode == .realtime
            ? ElevenLabsTranscriptionContract.realtimeModelID
            : ElevenLabsTranscriptionContract.uploadModelID
        )
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
      }

      settingsToggle(
        "Clean up spoken disfluencies",
        detail: "Use Scribe's non-verbatim mode for more readable speech.",
        isOn: appState.settingsBinding(\.elevenLabsNoVerbatim))

      if appState.settings.transcriptionMode == .realtime {
        labeledPicker("Commit strategy") {
          Picker("Commit strategy", selection: appState.settingsBinding(\.elevenLabsCommitStrategy))
          {
            ForEach(ElevenLabsCommitStrategy.allCases) { strategy in
              Text(strategy.title).tag(strategy)
            }
          }
          .labelsHidden()
        }

        if appState.settings.elevenLabsCommitStrategy == .vad {
          Stepper(
            "VAD silence: \(appState.settings.elevenLabsVADSilenceThreshold, specifier: "%.1f") s",
            value: appState.settingsBinding(\.elevenLabsVADSilenceThreshold),
            in: 0.3...3,
            step: 0.1
          )
          LabeledContent("VAD threshold") {
            HStack(spacing: 10) {
              Slider(
                value: appState.settingsBinding(\.elevenLabsVADThreshold),
                in: 0.1...0.9,
                step: 0.05
              )
              Text(
                appState.settings.elevenLabsVADThreshold,
                format: .number.precision(.fractionLength(2))
              )
              .font(.callout.monospacedDigit())
              .frame(width: 36, alignment: .trailing)
            }
            .frame(maxWidth: 280)
          }
          Stepper(
            "Minimum speech: \(appState.settings.elevenLabsMinSpeechDuration) ms",
            value: appState.settingsBinding(\.elevenLabsMinSpeechDuration),
            in: 50...2000,
            step: 50
          )
          Stepper(
            "Minimum silence: \(appState.settings.elevenLabsMinSilenceDuration) ms",
            value: appState.settingsBinding(\.elevenLabsMinSilenceDuration),
            in: 50...2000,
            step: 50
          )
        }
      }
    }
  }

  var deliveryStageSettings: some View {
    VStack(alignment: .leading, spacing: 14) {
      workflowStageHeader(
        "Deliver",
        description:
          "Control clipboard and history retention after the transcript returns to your app.",
        systemImage: "text.insert"
      )

      settingsToggle(
        "Keep a copy on the clipboard",
        detail:
          "Vhrase always returns text to the app where you started dictating. Keep the same text ready to paste elsewhere.",
        isOn: appState.settingsBinding(\.keepTranscriptOnClipboard)
      )

      Divider()

      settingsToggle(
        "Save transcripts to history",
        detail:
          "Keep future transcripts on this Mac. Turning this off does not delete anything already saved.",
        isOn: Binding(
          get: { appState.savesTranscriptHistory },
          set: { appState.updateTranscriptHistorySaving($0) }
        )
      )
    }
    .toggleStyle(.switch)
  }

  var enhancementStageSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      workflowStageHeader(
        "Enhance",
        description: "Optionally send the corrected transcript through your LLM before delivery.",
        systemImage: "wand.and.stars"
      )

      settingsToggle(
        "Enhance with an LLM",
        detail: "Apply your writing instructions before delivery.",
        isOn: appState.settingsBinding(\.adjustWithLLM)
      )

      if appState.settings.adjustWithLLM {
        Divider()

        compactField("Model", text: appState.settingsBinding(\.adjustmentModel))

        settingsToggle(
          "Use screen context",
          detail: "Send a screenshot to the configured LLM endpoint for additional context.",
          isOn: appState.settingsBinding(\.includeScreenshot)
        )

        settingsToggle(
          "Use local cleanup if the LLM fails",
          detail: "Return a locally normalized transcript instead of blocking delivery.",
          isOn: appState.settingsBinding(\.useLocalAdjustmentFallback)
        )

        editorTile(
          "Writing instructions",
          systemImage: "text.alignleft",
          text: appState.settingsBinding(\.adjustmentPrompt),
          height: 150
        )

        Button {
          appState.checkLLMModelAccess()
        } label: {
          Label(
            appState.isCheckingLLMModelAccess ? "Checking model…" : "Check model access",
            systemImage: "checkmark.seal"
          )
        }
        .buttonStyle(.bordered)
        .disabled(appState.isCheckingLLMModelAccess)
      } else {
        Label(
          "This stage is bypassed. Corrected text goes directly to delivery.",
          systemImage: "arrow.right"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .toggleStyle(.switch)
  }

  var triggerStageSettings: some View {
    VStack(alignment: .leading, spacing: 14) {
      workflowStageHeader(
        "Trigger",
        description: "Set the global shortcut that starts and finishes dictation.",
        systemImage: "keyboard"
      )

      VStack(spacing: 14) {
        KeyCap(text: appState.settings.hotkeyDisplay, prominence: .hero)
          .scaleEffect(isCapturingHotkey ? 1.06 : 1)

        Text(
          isCapturingHotkey
            ? "Press Fn/Globe or another shortcut. Press Escape to cancel."
            : appState.settings.shortcutBehavior.summary
        )
        .font(.callout)
        .foregroundStyle(isCapturingHotkey ? VhraseTheme.accent : Color.secondary)
        .multilineTextAlignment(.center)
        .contentTransition(.interpolate)

        HStack(spacing: 10) {
          Button {
            appState.beginShortcutCapture()
            isCapturingHotkey = true
          } label: {
            Label(isCapturingHotkey ? "Listening" : "Change shortcut", systemImage: "record.circle")
          }
          .buttonStyle(.borderedProminent)
          .tint(VhraseTheme.accent)
          .disabled(isCapturingHotkey)

          Button {
            appState.disableShortcut()
          } label: {
            Label("Disable", systemImage: "slash.circle")
          }
          .buttonStyle(.bordered)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 154)
      .padding(.vertical, 20)
      .overlay(alignment: .bottom) {
        Divider()
      }
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
        value: isCapturingHotkey
      )

      if isCapturingHotkey {
        HotkeyCaptureView(isCapturing: $isCapturingHotkey) { hotkey in
          appState.setCustomShortcut(hotkey)
        } onFnCapture: {
          appState.setFnShortcut()
        } onCancel: {
          appState.cancelShortcutCapture()
        } onUnsupported: { message in
          appState.rejectShortcutCapture(message)
        }
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
      }

      labeledPicker("Shortcut") {
        Picker("Shortcut", selection: appState.settingsBinding(\.hotkeyPreset)) {
          ForEach(appState.settings.availableHotkeyPresets) { preset in
            Text(preset.display).tag(preset)
          }
        }
        .labelsHidden()
      }

      labeledPicker("Behavior") {
        Picker("Behavior", selection: appState.settingsBinding(\.shortcutBehavior)) {
          ForEach(ShortcutBehavior.allCases) { behavior in
            Text(behavior.title).tag(behavior)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }
    }
  }

  var listeningStageSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      workflowStageHeader(
        "Listen",
        description:
          "Choose your microphone, check its sound, and tell recognition which language to expect.",
        systemImage: "mic.fill"
      )

      labeledPicker("Input device") {
        Picker("Input device", selection: appState.settingsBinding(\.inputDeviceUID)) {
          Text("System default").tag("")
          ForEach(inputDevices) { device in
            Text(device.name).tag(device.id)
          }
          if !appState.settings.inputDeviceUID.isEmpty,
            !inputDevices.contains(where: { $0.id == appState.settings.inputDeviceUID })
          {
            Text("Selected microphone (disconnected)").tag(appState.settings.inputDeviceUID)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }
      .onAppear { refreshInputDevices() }
      .onReceive(
        NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)
      ) { _ in
        refreshInputDevices()
      }
      .onReceive(
        NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)
      ) { _ in
        refreshInputDevices()
      }
      if !inputDeviceError.isEmpty {
        Text(inputDeviceError).font(.caption).foregroundStyle(.secondary)
      }

      if appState.settings.provider == .gemini {
        compactField("Language hints", text: appState.settingsBinding(\.geminiLanguageHints))
        Text(
          "Optional BCP-47 codes separated by commas, such as en-US, yue-Hant-HK. Leave blank for automatic detection and code-switching."
        )
        .font(.caption).foregroundStyle(.secondary)
      } else {
        compactField("Language", text: appState.settingsBinding(\.language))
        Text(
          appState.settings.provider == .xai
            ? "Grok detects spoken language automatically. This code enables number and currency formatting when that option is on, such as en."
            : "Use a language code such as en, yue, or zh. Leave blank for automatic detection."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Divider()

      MicrophonePreviewView(
        preview: appState.audioInputPreview,
        settings: appState.settings,
        canPreview: appState.status.canStartRecording
      )

      Toggle("Automatic volume leveling", isOn: appState.settingsBinding(\.automaticVolumeLeveling))
      Text(
        "Gently levels microphone audio locally. These controls never change speaker or headphone volume."
      )
      .font(.caption).foregroundStyle(.secondary)

      LabeledContent("Volume adjustment") {
        Slider(value: appState.settingsBinding(\.inputGainDB), in: -6...6, step: 1)
          .accessibilityLabel("Volume adjustment in decibels")
        Text("\(Int(appState.settings.inputGainDB)) dB")
          .monospacedDigit().frame(width: 48, alignment: .trailing)
      }
      LabeledContent("Noise reduction") {
        Slider(
          value: Binding(
            get: { -appState.settings.noiseReductionDB },
            set: { value in appState.updateSettings { $0.noiseReductionDB = -value } }
          ), in: -12...0, step: 1
        ) {
          Text("Noise reduction")
        } minimumValueLabel: {
          Text("−12 dB")
        } maximumValueLabel: {
          Text("0")
        }
        .labelsHidden()
        .accessibilityValue("\(-Int(appState.settings.noiseReductionDB)) decibels")
        Text(
          appState.settings.noiseReductionDB == 0
            ? "0 dB" : "−\(Int(appState.settings.noiseReductionDB)) dB"
        )
        .monospacedDigit().frame(width: 48, alignment: .trailing)
      }
      Text(
        "A light reduction of steady background noise, applied locally to both upload and realtime audio. Values closer to zero preserve more of the original sound."
      )
      .font(.caption).foregroundStyle(.secondary)

      Divider()

      HStack(spacing: 12) {
        Label(
          "Your microphone choice applies to preview and dictation.",
          systemImage: "mic.and.signal.meter"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Spacer()
        Button {
          selectedTab = .system
          appState.refreshPermissions()
        } label: {
          Label("Review microphone access", systemImage: "arrow.up.right")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  var correctionStageSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      workflowStageHeader(
        "Correct",
        description: "Apply exact substitutions before optional LLM enhancement.",
        systemImage: "text.badge.checkmark"
      )

      editorTile(
        "Replacement rules",
        systemImage: "arrow.left.arrow.right",
        text: appState.settingsBinding(\.replacementRules),
        height: 220
      )

      Text(
        "Enter one rule per line, for example: spoken form => preferred form. Matching ignores case and accents."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  var customizationActions: some View {
    HStack(spacing: 8) {
      Button {
        appState.importCustomization()
      } label: {
        Label("Import", systemImage: "square.and.arrow.down")
      }
      Button {
        appState.exportCustomization()
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .help("Import or export language, vocabulary, replacements, and writing preferences")
  }

  var systemTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        pageHeader(
          "System",
          description: "Manage provider credentials, macOS access, and optional capabilities.",
          systemImage: MainWindowTab.system.systemImage
        )

        setupOverviewCard
          .hoverLift()

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 20) {
            keysCard
              .frame(minWidth: 430, maxWidth: 460)
              .hoverLift()

            VStack(spacing: 16) {
              permissionsCard
                .frame(minWidth: 470)
                .hoverLift()
              diagnosticsFullCard
                .hoverLift()
            }
            .frame(maxWidth: .infinity)
          }

          VStack(spacing: 16) {
            keysCard
              .hoverLift()
            permissionsCard
              .hoverLift()
            diagnosticsFullCard
              .hoverLift()
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: 1040, alignment: .topLeading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  var setupOverviewCard: some View {
    let diagnostic = primarySetupDiagnostic
    return HStack(alignment: .center, spacing: 14) {
      Image(systemName: diagnostic.systemImage)
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(VhraseTheme.diagnosticColor(diagnostic.severity))
        .frame(width: 48, height: 48)
        .background(
          VhraseTheme.diagnosticColor(diagnostic.severity).opacity(0.12),
          in: Circle()
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(setupOverviewTitle(diagnostic))
          .font(.title3.weight(.semibold))
          .tracking(-0.2)
        Text(setupOverviewDetail(diagnostic))
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 16)

      if let actionTitle = setupDiagnosticActionTitle(diagnostic) {
        Button(actionTitle) {
          handleSetupDiagnostic(primarySetupDiagnostic)
        }
        .buttonStyle(.borderedProminent)
        .tint(VhraseTheme.accent)
        .disabled(
          diagnostic.id == "opencc-s2hk"
            && appState.openCCInstallationState == .installing
        )
      }
    }
    .operationalSurface()
  }

  var keysCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader(
        "Provider credentials",
        description:
          "Saved keys stay in your login Keychain. LLM_BASE_URL overrides the saved endpoint when present.")

      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
        keyField("xAI API key", key: .xaiAPIKey, text: apiKeyBinding(.xaiAPIKey))
        keyField(
          "ElevenLabs API key", key: .elevenLabsAPIKey, text: apiKeyBinding(.elevenLabsAPIKey))
        keyField("Gemini API key", key: .geminiAPIKey, text: apiKeyBinding(.geminiAPIKey))
        keyField("LLM API key", key: .llmAPIKey, text: apiKeyBinding(.llmAPIKey))
        configurationField(
          "LLM base URL",
          text: Binding(
            get: { appState.effectiveLLMBaseURL },
            set: { value in
              guard !appState.usesEnvironmentLLMBaseURL else { return }
              appState.updateSettings { $0.adjustmentBaseURL = value }
            }
          ),
          environmentName: appState.usesEnvironmentLLMBaseURL ? "LLM_BASE_URL" : nil
        )
      }
      .frame(maxWidth: .infinity)

      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10
      ) {
        keyStatus(
          "xAI",
          isReady: !appState.effectiveXAIAPIKey.isEmpty,
          usesEnvironmentFallback: appState.usesEnvironmentFallback(for: .xaiAPIKey)
        )
        keyStatus(
          "ElevenLabs",
          isReady: !appState.effectiveElevenLabsAPIKey.isEmpty,
          usesEnvironmentFallback: appState.usesEnvironmentFallback(for: .elevenLabsAPIKey)
        )
        keyStatus(
          "LLM",
          isReady: !appState.effectiveLLMAPIKey.isEmpty,
          usesEnvironmentFallback: appState.usesEnvironmentFallback(for: .llmAPIKey)
        )
        keyStatus(
          "Gemini", isReady: !appState.effectiveGeminiAPIKey.isEmpty,
          usesEnvironmentFallback: appState.usesEnvironmentFallback(for: .geminiAPIKey))
      }

      HStack(spacing: 10) {
        Button {
          appState.checkLLMModelAccess()
        } label: {
          HStack(spacing: 6) {
            if appState.isCheckingLLMModelAccess {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "bolt.horizontal.circle")
            }
            Text(appState.isCheckingLLMModelAccess ? "Testing LLM…" : "Test LLM")
          }
        }
        .buttonStyle(.bordered)
        .disabled(appState.isCheckingLLMModelAccess || appState.effectiveLLMAPIKey.isEmpty)

        Text("Sends only a tiny “Reply with OK” request using the configured model.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(
        "Credentials save automatically without password dialogs. If Keychain access is blocked, edits stay in memory for this session."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      if !appState.unsavedAPIKeys.isEmpty {
        HStack {
          Label("Unsaved credential changes", systemImage: "exclamationmark.circle")
            .foregroundStyle(VhraseTheme.statusWarning)
          Spacer()
          Button("Retry saving") { appState.retrySavingAPIKeys() }
        }
        .font(.caption)
      }

      if !appState.keychainReadNotice.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Label("Saved credentials need Keychain access", systemImage: "lock")
            .font(.callout.weight(.medium))
          Text(appState.keychainReadNotice)
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Retry reading saved keys") { appState.retryLoadingAPIKeys() }
        }
      }
    }
    .contentSection()
  }

  private func keyField(
    _ title: String,
    key: SecretKey,
    text: Binding<String>
  ) -> some View {
    GridRow {
      Text(title)
        .font(.callout.weight(.medium))
        .gridColumnAlignment(.trailing)

      Group {
        if showsCredentialReference(text.wrappedValue) {
          TextField(title, text: text)
        } else {
          SecureField(title, text: text)
        }
      }
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 280, maxWidth: .infinity)
        .gridColumnAlignment(.leading)
        .transaction { transaction in
          transaction.animation = nil
        }
        .focused($focusedSecretField, equals: key.rawValue)
        .onSubmit {
          finishAPIKeyEditing()
        }
    }
  }

  private func showsCredentialReference(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { byte in
      byte == 95 || (65...90).contains(byte)
    }
  }

  private func configurationField(
    _ title: String,
    text: Binding<String>,
    environmentName: String?
  ) -> some View {
    GridRow {
      Text(title)
        .font(.callout.weight(.medium))
        .gridColumnAlignment(.trailing)

      VStack(alignment: .leading, spacing: 5) {
        TextField(title, text: text)
          .textFieldStyle(.roundedBorder)
          .disabled(environmentName != nil)
        if let environmentName {
          Label("Loaded from \(environmentName)", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(VhraseTheme.statusSuccess)
        }
      }
      .frame(minWidth: 280, maxWidth: .infinity)
      .gridColumnAlignment(.leading)
    }
  }

  var permissionsCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        sectionHeader(
          "Permissions",
          description: "Grant only the macOS access required by the features you use.")
        Spacer()
        Button {
          appState.refreshPermissions()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        if let microphone = presentation.permissionSnapshot(.microphone),
          !microphone.state.isReady
        {
          Button {
            appState.handlePermissionAction(microphone)
          } label: {
            Label(
              microphone.state == .notDetermined
                ? "Request Microphone" : "Open Microphone Settings",
              systemImage: "mic.badge.plus"
            )
          }
        }
      }

      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())],
        alignment: .leading,
        spacing: 10
      ) {
        ForEach(relevantPermissionSnapshots) { snapshot in
          permissionTile(snapshot)
        }
      }

      Text(
        "Microphone is required. Shortcut, paste, and screen access appear only when the features you chose need them."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .contentSection()
  }

  var diagnosticsFullCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(
        "Readiness details",
        description: "Review the selected provider, permissions, and optional capabilities.")

      ForEach(appState.setupDiagnostics) { diagnostic in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: diagnostic.systemImage)
            .foregroundStyle(VhraseTheme.diagnosticColor(diagnostic.severity))
            .frame(width: 22)
          VStack(alignment: .leading, spacing: 2) {
            Text(diagnostic.title)
              .font(.headline)
            Text(diagnostic.detail)
              .font(.callout)
              .foregroundStyle(.secondary)
            if diagnostic.id == "opencc-s2hk",
              let failureMessage = appState.openCCInstallationState.failureMessage
            {
              Text(failureMessage)
                .font(.caption)
                .foregroundStyle(VhraseTheme.statusWarning)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          Spacer()
          if diagnostic.id == "opencc-s2hk",
            appState.openCCInstallationState == .installing
          {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("Installing OpenCC")
          }
          if let actionTitle = setupDiagnosticActionTitle(diagnostic) {
            Button(actionTitle) {
              handleSetupDiagnostic(diagnostic)
            }
            .buttonStyle(.bordered)
            .disabled(
              diagnostic.id == "opencc-s2hk"
                && appState.openCCInstallationState == .installing
            )
          }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
      }
    }
    .contentSection()
  }

}
