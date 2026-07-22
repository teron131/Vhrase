// Implements the sidebar destinations and complete configuration workflows for Vhrase's main window.

import AppKit
import SwiftUI

extension MainWindowView {
    var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                        Text("Vhrase")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                    ForEach(MainWindowTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.systemImage)
                                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)
                                Text(tab.title)
                                    .fontWeight(selectedTab == tab ? .medium : .regular)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 8)
                            .background(
                                selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
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

            HStack(spacing: 8) {
                Circle()
                    .fill(presentation.coreRecordingReady ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(presentation.coreRecordingReady ? "Ready to dictate" : "Setup needed")
                    .fontWeight(.medium)
            }

            HStack {
                Text("Shortcut")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.settings.hotkeyDisplay)
                    .font(.callout.monospaced())
            }

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Vhrase settings")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .background(.bar)
    }

    var dictationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recordPanel
                transcriptCard
                quickActionsCard
            }
            .frame(maxWidth: 820, alignment: .topLeading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    var recordPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: statusSystemImage)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 48, height: 48)
                    .background(statusColor.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusShortTitle)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .tracking(-0.35)
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Button {
                    handleRecordButton()
                } label: {
                    Label(recordButtonTitle, systemImage: recordButtonSystemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(recordButtonTint)
                .disabled(presentation.recordAction == .disabled)
                .accessibilityHint(recordButtonSubtitle)
            }

            if appState.status == .preparing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(statusColor)
            } else if appState.isRecording {
                VStack(alignment: .leading, spacing: 7) {
                    audioMeter
                    HStack {
                        Text(elapsedTime)
                            .font(.callout.monospacedDigit())
                        Spacer()
                        if !appState.targetAppLabel.isEmpty {
                            Label(appState.targetAppLabel, systemImage: "app")
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 16) {
                Label(
                    "\(appState.settings.provider.title) \(appState.settings.transcriptionMode.title.lowercased())",
                    systemImage: "dot.radiowaves.left.and.right"
                )
                Label(
                    appState.settings.adjustWithLLM ? "LLM cleanup" : "Raw output",
                    systemImage: appState.settings.adjustWithLLM ? "wand.and.stars" : "text.alignleft"
                )
                Spacer(minLength: 8)
                Label(appState.settings.hotkeyDisplay, systemImage: "keyboard")
                    .font(.caption.monospaced().weight(.medium))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .operationalSurface(tint: statusColor)
        .animation(.easeInOut(duration: 0.2), value: statusShortTitle)
    }

    var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(transcriptWorkspaceTitle, systemImage: transcriptWorkspaceSystemImage)
                        .font(.headline)
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
                    .disabled(transcriptWorkspaceCopyText.isEmpty)
                    .accessibilityHint("Copies the displayed transcript to the clipboard")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if appState.isRecording {
                    audioMeter
                }

                Text(transcriptWorkspaceText)
                    .font(.body)
                    .foregroundStyle(transcriptWorkspaceIsPlaceholder ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(16)
            .background(AppTheme.field.opacity(0.78), in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.hairline.opacity(0.5), lineWidth: 1)
            }

            if !appState.lastAdjustmentWarning.isEmpty {
                Label(appState.lastAdjustmentWarning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .contentSection()
    }

    var quickActionsCard: some View {
        HStack(spacing: 10) {
            Button {
                appState.runDemoDictation()
            } label: {
                Label("Run demo", systemImage: "play.circle")
            }
            .disabled(!appState.status.canStartRecording)

            Spacer()

            Button {
                selectedTab = .customize
            } label: {
                Label("Writing options", systemImage: "slider.horizontal.3")
            }

            Button {
                selectedTab = .setup
                appState.refreshPermissions()
            } label: {
                Label("Check setup", systemImage: "checkmark.shield")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 4)
    }

    var customizeTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                providerControls
                customizationControls
                buttonCustomizationCard
                textCustomization
            }
            .frame(maxWidth: 820, alignment: .topLeading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .disabled(presentation.workflowControlsAreDisabled)
    }

    var providerControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Transcription", systemImage: "waveform.badge.mic")
                .font(.title3.weight(.semibold))

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

            providerSpecificControls
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

    var customizationControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Output and cleanup", systemImage: "wand.and.stars")
                .font(.title3.weight(.semibold))

            Toggle("Paste after transcription", isOn: persistedBinding(\.pasteAfterTranscription))

            Toggle("Clean up with an LLM", isOn: persistedBinding(\.adjustWithLLM))

            Toggle("Use screenshot context", isOn: persistedBinding(\.includeScreenshot))
                .disabled(!appState.settings.adjustWithLLM)

            Toggle("Use local cleanup if the LLM fails", isOn: persistedBinding(\.useLocalAdjustmentFallback))
                .disabled(!appState.settings.adjustWithLLM)

            if appState.settings.adjustWithLLM {
                compactField("Adjustment model", text: persistedBinding(\.adjustmentModel))
                compactField("LLM base URL", text: persistedBinding(\.adjustmentBaseURL))

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
            Label("Global shortcut", systemImage: "keyboard")
                .font(.title3.weight(.semibold))

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.settings.hotkeyDisplay)
                        .font(.title2.monospaced())
                    Text(isCapturingHotkey ? "Press Fn/Globe or another shortcut. Press Escape to cancel." : appState.settings.shortcutBehavior.summary)
                        .font(.callout)
                        .foregroundStyle(isCapturingHotkey ? Color.accentColor : Color.secondary)
                }

                Spacer()

                Button {
                    appState.beginShortcutCapture()
                    isCapturingHotkey = true
                } label: {
                    Label(isCapturingHotkey ? "Listening" : "Set shortcut", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCapturingHotkey)

                Button {
                    appState.disableShortcut()
                } label: {
                    Label("Disable", systemImage: "slash.circle")
                }
                .buttonStyle(.bordered)
            }

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

    var textCustomization: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Vocabulary and instructions", systemImage: "text.badge.plus")
                .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: 16) {
                editorTile(
                    "Keyterms",
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

            if appState.settings.adjustWithLLM {
                editorTile(
                    "Adjustment prompt",
                    systemImage: "text.alignleft",
                    text: persistedBinding(\.adjustmentPrompt),
                    height: 130
                )
            }

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
        }
        .contentSection()
    }

    var setupTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                setupOverviewCard
                keysCard
                permissionsCard
                diagnosticsFullCard
            }
            .frame(maxWidth: 820, alignment: .topLeading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    var setupOverviewCard: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: primarySetupDiagnostic.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(diagnosticColor(primarySetupDiagnostic.severity))
                .frame(width: 46, height: 46)
                .background(
                    diagnosticColor(primarySetupDiagnostic.severity).opacity(0.12),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(setupOverviewTitle)
                    .font(.title3.weight(.semibold))
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
            }
        }
        .operationalSurface(tint: diagnosticColor(primarySetupDiagnostic.severity))
    }

    var keysCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("API keys", systemImage: "key")
                .font(.title3.weight(.semibold))

            keyField("xAI API key", key: .xaiAPIKey, text: apiKeyBinding(.xaiAPIKey, \.xaiAPIKey))
            keyField("ElevenLabs API key", key: .elevenLabsAPIKey, text: apiKeyBinding(.elevenLabsAPIKey, \.elevenLabsAPIKey))
            keyField("LLM API key", key: .llmAPIKey, text: apiKeyBinding(.llmAPIKey, \.llmAPIKey))

            HStack(spacing: 16) {
                keyStatus(
                    "xAI",
                    isReady: !appState.effectiveXAIAPIKey.isEmpty,
                    usesEnvironmentOverride: appState.usesEnvironmentOverride(for: .xaiAPIKey)
                )
                keyStatus(
                    "ElevenLabs",
                    isReady: !appState.effectiveElevenLabsAPIKey.isEmpty,
                    usesEnvironmentOverride: appState.usesEnvironmentOverride(for: .elevenLabsAPIKey)
                )
                keyStatus(
                    "LLM",
                    isReady: !appState.effectiveLLMAPIKey.isEmpty,
                    usesEnvironmentOverride: appState.usesEnvironmentOverride(for: .llmAPIKey)
                )
            }

            Text("Keys are stored in your login Keychain after you finish editing.")
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
        LabeledContent(title) {
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .disabled(appState.usesEnvironmentOverride(for: key))
                .focused($focusedSecretField, equals: key.rawValue)
                .onSubmit {
                    flushPendingAPIKeySave()
                }
        }
    }

    var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Permissions", systemImage: "lock.shield")
                    .font(.title3.weight(.semibold))
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
                ForEach(appState.permissions) { snapshot in
                    permissionTile(snapshot)
                }
            }

            Text("Microphone is required. Input Monitoring is only needed for Fn/Globe; Screen Recording and Accessibility support screenshot context and automatic paste.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentSection()
    }

    var diagnosticsFullCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Setup check", systemImage: "stethoscope")
                .font(.title3.weight(.semibold))

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
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .contentSection()
    }

}
