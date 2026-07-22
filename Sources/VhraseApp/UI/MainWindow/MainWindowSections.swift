// Implements the sidebar destinations and complete configuration workflows for Vhrase's main window.

import AppKit
import SwiftUI

extension MainWindowView {
    var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(VhraseTheme.accent)
                            .frame(width: 8, height: 8)
                            .rotationEffect(appState.isRecording ? .degrees(45) : .zero)
                            .scaleEffect(appState.isRecording ? 1.22 : 1)
                            .animation(
                                VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
                                value: appState.isRecording
                            )
                        Text("Vhrase")
                            .font(VhraseFont.title)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)

                    ForEach(MainWindowTab.allCases) { tab in
                        Button {
                            withAnimation(
                                VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion)
                            ) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.systemImage)
                                    .font(.callout)
                                    .foregroundStyle(selectedTab == tab ? VhraseTheme.accent : VhraseTheme.inkSecondary)
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
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 8)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(VhraseTheme.accentSubtle)
                                        .matchedGeometryEffect(id: "navigation-selection", in: navigationSelection)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

    var dictationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader(
                    "Dictate",
                    description: "Speak naturally, review the result, and keep writing without changing apps.",
                    systemImage: MainWindowTab.dictate.systemImage
                )
                .revealOnAppear()

                HStack(alignment: .top, spacing: 24) {
                    recordPanel
                        .frame(width: 310)
                        .hoverLift()
                        .revealOnAppear()

                    transcriptCard
                        .frame(maxWidth: .infinity)
                        .hoverLift()
                        .revealOnAppear(delay: 0.08)
                }
                quickActionsCard
                    .revealOnAppear(delay: 0.16)
            }
            .frame(maxWidth: 1040, alignment: .topLeading)
            .padding(36)
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
            RecordHeroButton(
                presentation: presentation,
                recordingLevel: appState.recordingLevel,
                style: .hero,
                action: handleRecordButton
            )

            Text(presentation.displayStatusTitle)
                .font(VhraseFont.display)
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
        .shadow(color: presentation.statusTint.opacity(presentation.coreRecordingReady ? 0.16 : 0), radius: 24, y: 8)
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

            if !appState.lastAdjustmentWarning.isEmpty {
                NoticeCard(
                    appState.lastAdjustmentWarning,
                    systemImage: "exclamationmark.triangle",
                    color: VhraseTheme.statusWarning,
                    actionTitle: presentation.pastePermissionActionTitle,
                    action: handlePastePermissionAction
                )
            }
        }
        .contentSection()
    }

    var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("Activity", description: "A lightweight view of your local dictation activity.")
                Spacer()
                Button("View history") {
                    selectedTab = .history
                }
                .buttonStyle(.link)
                .disabled(appState.history.isEmpty)
            }

            HStack(spacing: 18) {
                activityMetric(
                    "Today",
                    value: "\(transcriptsTodayCount)",
                    detail: "completed dictations"
                )
                Divider()
                    .frame(height: 48)
                activityMetric(
                    "Saved",
                    value: "\(appState.history.count)",
                    detail: "on this Mac"
                )
                Divider()
                    .frame(height: 48)
                activityMetric(
                    "History",
                    value: appState.savesTranscriptHistory ? "On" : "Off",
                    detail: appState.savesTranscriptHistory ? "saving new transcripts" : "not saving new transcripts"
                )
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
            .buttonStyle(.link)
        }
        .contentSection()
    }

    var captureTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    "Capture",
                    description: "Choose how Vhrase listens and which shortcut follows you across apps.",
                    systemImage: MainWindowTab.capture.systemImage
                )
                .revealOnAppear()

                HStack(alignment: .top, spacing: 20) {
                    providerControls
                        .frame(maxWidth: .infinity)
                        .hoverLift()
                        .revealOnAppear(delay: 0.06)
                    buttonCustomizationCard
                        .frame(maxWidth: .infinity)
                        .hoverLift()
                        .revealOnAppear(delay: 0.12)
                }
            }
            .frame(maxWidth: 1040, alignment: .topLeading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .disabled(presentation.workflowControlsAreDisabled)
    }

    var outputTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    "Output",
                    description: "Decide where transcripts go and how Vhrase shapes the final wording.",
                    systemImage: MainWindowTab.output.systemImage
                )
                .revealOnAppear()

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        deliveryControls
                        llmCleanupControls
                    }
                    .frame(width: 340)

                    VStack(spacing: 16) {
                        vocabularyControls
                        if appState.settings.adjustWithLLM {
                            writingInstructionsCard
                        }
                        customizationTransferBar
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 1040, alignment: .topLeading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .disabled(presentation.workflowControlsAreDisabled)
    }

    var providerControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Speech recognition", description: "Select the service, response mode, and spoken language.")

            labeledPicker("Provider") {
                Picker("Provider", selection: persistedBinding(\.provider)) {
                    ForEach(STTProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            labeledPicker("Mode") {
                Picker("Mode", selection: persistedBinding(\.transcriptionMode)) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            compactField("Language", text: persistedBinding(\.language))

            DisclosureGroup("Advanced provider settings") {
                VStack(alignment: .leading, spacing: 12) {
                    providerSpecificControls
                }
                .padding(.top, 10)
            }
        }
        .toggleStyle(.switch)
        .contentSection()
    }

    @ViewBuilder
    private var providerSpecificControls: some View {
        switch appState.settings.provider {
        case .xai:
            Toggle("Include filler words", isOn: persistedBinding(\.includeFillerWords))

            if appState.settings.transcriptionMode == .realtime {
                Stepper(
                    "Endpointing: \(appState.settings.xaiRealtimeEndpointing) ms",
                    value: persistedBinding(\.xaiRealtimeEndpointing),
                    in: 0...5000,
                    step: 100
                )

                Toggle("Smart Turn", isOn: persistedBinding(\.xaiSmartTurnEnabled))

                if appState.settings.xaiSmartTurnEnabled {
                    LabeledContent("Smart Turn threshold") {
                        HStack(spacing: 10) {
                            Slider(
                                value: persistedBinding(\.xaiSmartTurnThreshold),
                                in: 0...1,
                                step: 0.05
                            )
                            Text(appState.settings.xaiSmartTurnThreshold, format: .number.precision(.fractionLength(2)))
                                .font(.callout.monospacedDigit())
                                .frame(width: 36, alignment: .trailing)
                        }
                        .frame(maxWidth: 280)
                    }
                    Stepper(
                        "Smart Turn timeout: \(appState.settings.xaiSmartTurnTimeout) ms",
                        value: persistedBinding(\.xaiSmartTurnTimeout),
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

            Toggle("No verbatim", isOn: persistedBinding(\.elevenLabsNoVerbatim))

            if appState.settings.transcriptionMode == .realtime {
                labeledPicker("Commit strategy") {
                    Picker("Commit strategy", selection: persistedBinding(\.elevenLabsCommitStrategy)) {
                        ForEach(ElevenLabsCommitStrategy.allCases) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }
                    .labelsHidden()
                }

                if appState.settings.elevenLabsCommitStrategy == .vad {
                    Stepper(
                        "VAD silence: \(appState.settings.elevenLabsVADSilenceThreshold, specifier: "%.1f") s",
                        value: persistedBinding(\.elevenLabsVADSilenceThreshold),
                        in: 0.3...3,
                        step: 0.1
                    )
                    LabeledContent("VAD threshold") {
                        HStack(spacing: 10) {
                            Slider(
                                value: persistedBinding(\.elevenLabsVADThreshold),
                                in: 0.1...0.9,
                                step: 0.05
                            )
                            Text(appState.settings.elevenLabsVADThreshold, format: .number.precision(.fractionLength(2)))
                                .font(.callout.monospacedDigit())
                                .frame(width: 36, alignment: .trailing)
                        }
                        .frame(maxWidth: 280)
                    }
                    Stepper(
                        "Minimum speech: \(appState.settings.elevenLabsMinSpeechDuration) ms",
                        value: persistedBinding(\.elevenLabsMinSpeechDuration),
                        in: 50...2000,
                        step: 50
                    )
                    Stepper(
                        "Minimum silence: \(appState.settings.elevenLabsMinSilenceDuration) ms",
                        value: persistedBinding(\.elevenLabsMinSilenceDuration),
                        in: 50...2000,
                        step: 50
                    )
                }
            }
        }
    }

    var deliveryControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Delivery", description: "Choose what happens after a transcript is ready.")

            settingsToggle(
                "Paste into the active app",
                detail: "Insert the final text where you were typing. If access is unavailable, Vhrase copies it instead.",
                isOn: persistedBinding(\.pasteAfterTranscription)
            )

            Divider()

            settingsToggle(
                "Save transcripts to history",
                detail: "Keep future transcripts on this Mac. Turning this off does not delete anything already saved.",
                isOn: Binding(
                    get: { appState.savesTranscriptHistory },
                    set: { appState.updateTranscriptHistorySaving($0) }
                )
            )
        }
        .toggleStyle(.switch)
        .contentSection()
    }

    var llmCleanupControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("LLM cleanup", description: "Optionally refine wording after speech recognition finishes.")

            settingsToggle(
                "Clean up with an LLM",
                detail: "Apply your writing instructions before delivery.",
                isOn: persistedBinding(\.adjustWithLLM)
            )

            settingsToggle(
                "Use screen context",
                detail: "Send a screenshot to your configured LLM endpoint to improve context.",
                isOn: persistedBinding(\.includeScreenshot)
            )
                .disabled(!appState.settings.adjustWithLLM)

            settingsToggle(
                "Use local cleanup if the LLM fails",
                detail: "Return a locally normalized transcript instead of blocking delivery.",
                isOn: persistedBinding(\.useLocalAdjustmentFallback)
            )
                .disabled(!appState.settings.adjustWithLLM)

            if appState.settings.adjustWithLLM {
                compactField("Model", text: persistedBinding(\.adjustmentModel))
                compactField("Base URL", text: persistedBinding(\.adjustmentBaseURL))

                Button {
                    appState.checkLLMModelAccess()
                } label: {
                    Label("Check model access", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)
            }

            if !appState.customizationNotice.isEmpty {
                Label(appState.customizationNotice, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .toggleStyle(.switch)
        .contentSection()
    }

    var buttonCustomizationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Global shortcut", description: "Start and finish dictation without leaving the app you are writing in.")

            VStack(spacing: 14) {
                KeyCap(text: appState.settings.hotkeyDisplay, prominence: .hero)
                    .scaleEffect(isCapturingHotkey ? 1.06 : 1)

                Text(isCapturingHotkey ? "Press Fn/Globe or another shortcut. Press Escape to cancel." : appState.settings.shortcutBehavior.summary)
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
            .padding(16)
            .background(VhraseTheme.accentSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Picker("Shortcut", selection: persistedBinding(\.hotkeyPreset)) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.display).tag(preset)
                    }
                }
                .labelsHidden()
            }

            labeledPicker("Behavior") {
                Picker("Behavior", selection: persistedBinding(\.shortcutBehavior)) {
                    ForEach(ShortcutBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
        .contentSection()
    }

    var vocabularyControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Vocabulary", description: "Teach speech providers your preferred spellings and exact substitutions.")

            HStack(alignment: .top, spacing: 16) {
                editorTile(
                    "Preferred terms",
                    systemImage: "tag",
                    text: persistedBinding(\.keyterms),
                    height: 110
                )
                editorTile(
                    "Replacements",
                    systemImage: "arrow.left.arrow.right",
                    text: persistedBinding(\.replacementRules),
                    height: 110
                )
            }

            Text(keytermGuidance)
                .font(.caption)
                .foregroundStyle(appState.transcriptionConfigurationIssue == nil ? Color.secondary : Color.red)
        }
        .contentSection()
    }

    var writingInstructionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Writing instructions", description: "Tell the cleanup model how the final transcript should read.")

            editorTile(
                "Instructions",
                systemImage: "text.alignleft",
                text: persistedBinding(\.adjustmentPrompt),
                height: 130
            )
        }
        .contentSection()
    }

    var customizationTransferBar: some View {
        HStack(spacing: 10) {
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
            Spacer()
            Text(appState.settings.customizationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 4)
    }

    var systemTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader(
                    "System",
                    description: "Manage provider credentials, macOS access, and optional capabilities.",
                    systemImage: MainWindowTab.system.systemImage
                )
                .revealOnAppear()

                setupOverviewCard
                    .hoverLift()
                    .revealOnAppear()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        keysCard
                            .frame(minWidth: 430, maxWidth: 460)
                            .hoverLift()
                            .revealOnAppear(delay: 0.07)

                        VStack(spacing: 16) {
                            permissionsCard
                                .frame(minWidth: 470)
                                .hoverLift()
                                .revealOnAppear(delay: 0.12)
                            diagnosticsFullCard
                                .hoverLift()
                                .revealOnAppear(delay: 0.17)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 16) {
                        keysCard
                            .hoverLift()
                            .revealOnAppear(delay: 0.07)
                        permissionsCard
                            .hoverLift()
                            .revealOnAppear(delay: 0.12)
                        diagnosticsFullCard
                            .hoverLift()
                            .revealOnAppear(delay: 0.17)
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
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: primarySetupDiagnostic.systemImage)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(diagnosticColor(primarySetupDiagnostic.severity))
                .frame(width: 48, height: 48)
                .background(
                    diagnosticColor(primarySetupDiagnostic.severity).opacity(0.12),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(setupOverviewTitle)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.2)
                Text(setupOverviewDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if let actionTitle = setupDiagnosticActionTitle(primarySetupDiagnostic) {
                Button(actionTitle) {
                    handleSetupDiagnostic(primarySetupDiagnostic)
                }
                .buttonStyle(.borderedProminent)
                .tint(VhraseTheme.accent)
                .disabled(
                    primarySetupDiagnostic.id == "opencc-s2hk"
                        && appState.openCCInstallationState == .installing
                )
            }
        }
        .operationalSurface()
    }

    var keysCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Provider credentials", description: "Saved values stay in your login Keychain. Environment values fill only empty fields.")

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                keyField("xAI API key", key: .xaiAPIKey, text: apiKeyBinding(.xaiAPIKey))
                keyField("ElevenLabs API key", key: .elevenLabsAPIKey, text: apiKeyBinding(.elevenLabsAPIKey))
                keyField("LLM API key", key: .llmAPIKey, text: apiKeyBinding(.llmAPIKey))
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
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
            }

            Text("Credentials are saved after you finish editing each field.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 280, maxWidth: .infinity)
                .gridColumnAlignment(.leading)
                .focused($focusedSecretField, equals: key.rawValue)
                .onSubmit {
                    appState.flushPendingAPIKeySave()
                }
        }
    }

    var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("Permissions", description: "Grant only the macOS access required by the features you use.")
                Spacer()
                Button {
                    appState.refreshPermissions()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    appState.setupPermissionsOnce()
                } label: {
                    Label("Request Microphone", systemImage: "mic.badge.plus")
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

            Text("Microphone is required. Shortcut, paste, and screen access appear only when the features you chose need them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentSection()
    }

    var diagnosticsFullCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Readiness details", description: "Review the selected provider, permissions, and optional capabilities.")

            ForEach(appState.setupDiagnostics) { diagnostic in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: diagnostic.systemImage)
                        .foregroundStyle(diagnosticColor(diagnostic.severity))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.title)
                            .font(.headline)
                        Text(diagnostic.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if diagnostic.id == "opencc-s2hk",
                           let failureMessage = appState.openCCInstallationState.failureMessage {
                            Text(failureMessage)
                                .font(.caption)
                                .foregroundStyle(VhraseTheme.statusWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    if diagnostic.id == "opencc-s2hk",
                       appState.openCCInstallationState == .installing {
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
