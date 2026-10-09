// Owns capture configuration and releases shortcut editing and microphone preview when its window or destination is left.

import AVFoundation
import AppKit
import SwiftUI

struct CaptureView: View {
  @ObservedObject var appState: AppState
  @Binding var selectedTab: MainWindowTab
  @Binding var selectedCapturePipelineStage: PipelineStage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var isCapturingHotkey = false
  @State private var inputDevices: [AudioInputDevice] = []
  @State private var inputDeviceError = ""
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    captureTab
      .mainWindowEvents(
        appState: appState, blocksEscape: isCapturingHotkey,
        onActivate: resumePreview, onDeactivate: leaveCapture
      )
      .onChange(of: selectedCapturePipelineStage) { _, stage in
        if stage != .trigger { cancelShortcutCaptureIfNeeded() }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { refreshInputDevices() }
      }
      .onDisappear(perform: leaveCapture)
  }

  /// Navigation and window deactivation end temporary capture ownership, never the user's dictation.
  private func leaveCapture() {
    cancelShortcutCaptureIfNeeded()
    appState.audioInputPreview.stop()
  }

  /// A hidden window can become key without remounting its Listen view or changing the app's scene phase.
  private func resumePreview() {
    guard selectedCapturePipelineStage == .listen, appState.status.canStartRecording else { return }
    appState.audioInputPreview.start(settings: appState.settings)
  }

  private var captureTab: some View {
    mainWindowPage(spacing: 22) {
      pageHeader(
        MainWindowTab.capture.title,
        description: "Choose how Vhrase listens and which shortcut follows you across apps."
      )

      PipelineFlowView(
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
      )

      captureWorkflowStageEditor
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .id(selectedCapturePipelineStage)
        .transition(.opacity)
    }
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.settle, reduceMotion: reduceMotion),
      value: selectedCapturePipelineStage
    )
    .disabled(presentation.workflowControlsAreDisabled)
  }

  /// Repeated navigation to Listen reacquires capture without interrupting an active dictation.
  private func restartListeningPreview() {
    guard selectedCapturePipelineStage == .listen, appState.status.canStartRecording else { return }
    NSApp.activate()
    appState.audioInputPreview.restart(settings: appState.settings)
  }

  private func stageIntro(_ text: String) -> some View {
    Text(text)
      .font(VhraseFont.caption)
      .foregroundStyle(VhraseTheme.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var transcriptionStageSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      stageIntro("Choose the speech service and tune how it recognizes your words.")

      settingsGroup("Service", footer: serviceFooter) {
        ForEach(ProviderLocation.allCases) { location in
          settingsRow(location.title, detail: providerDetail(for: location)) {
            ProviderPicker(
              selection: appState.settingsBinding(\.provider),
              providers: location.providers,
              style: .segmented
            )
            .fixedSize()
          }
        }
        settingsRow(
          "Mode",
          detail: appState.settings.provider.location == .local
            ? "Transcribes on this Mac once you stop recording."
            : "Upload transcribes after you stop. Realtime transcribes while you speak."
        ) {
          TranscriptionModePicker(
            selection: appState.settingsBinding(\.transcriptionMode),
            provider: appState.settings.provider,
            enabledModes: appState.settings.provider.availableModes
          )
          .fixedSize()
        }
      }

      settingsGroup("\(appState.settings.provider.title) options") {
        providerSpecificControls
      }

      settingsGroup("Shared vocabulary") {
        VocabularyEditor(appState: appState)
          .settingsRowStyle()
      }
    }
  }

  /// Describes the chosen provider in its own location's row and what choosing the other location means.
  private func providerDetail(for location: ProviderLocation) -> String {
    let provider = appState.settings.provider
    if provider.location == location {
      return provider.detail
    }
    return switch location {
    case .cloud: "Sends your recording to the provider; each needs its API key."
    case .local: "Recognizes speech on this Mac after a one-time model download; no API key."
    }
  }

  private var serviceFooter: String? {
    switch appState.settings.provider {
    case .gemini:
      "Audio is sent directly to Google after you stop. Interaction storage is disabled. Live Gemini transcription is not enabled in this version."
    case .parakeet:
      "No audio leaves this Mac. Realtime streaming and vocabulary hints are not available for Parakeet."
    case .xai, .elevenLabs:
      nil
    }
  }

  @ViewBuilder
  private var providerSpecificControls: some View {
    switch appState.settings.provider {
    case .parakeet:
      ParakeetModelControls(appState: appState, model: appState.parakeetModel)
    case .gemini:
      settingsToggle(
        "Smart transcription",
        detail:
          "Remove fillers, resolve spoken corrections, and format paragraphs and lists. Turn off when you need closer preservation of the spoken words.",
        isOn: appState.settingsBinding(\.geminiSmartTranscription))
      if appState.settings.geminiSmartTranscription, appState.settings.adjustWithLLM {
        HStack(alignment: .center, spacing: 12) {
          Label(
            "LLM enhancement is also on. It will rewrite the Smart transcript a second time.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(VhraseTheme.statusWarning)
          .frame(maxWidth: .infinity, alignment: .leading)
          Button("Use Smart only") {
            appState.updateSettings { $0.adjustWithLLM = false }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        .settingsRowStyle()
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
        settingsSlider(
          "Speech detection threshold",
          detail:
            "Lower values can help with quiet speech but may transcribe background noise. Zero disables the gate; default is 0.08.",
          value: appState.settingsBinding(\.xaiVADThreshold),
          in: 0...1,
          step: 0.01,
          valueLabel: appState.settings.xaiVADThreshold.formatted(
            .number.precision(.fractionLength(2)))
        )
        settingsStepper(
          "Endpointing",
          value: appState.settingsBinding(\.xaiRealtimeEndpointing),
          in: 0...5000,
          step: 100,
          valueLabel: "\(appState.settings.xaiRealtimeEndpointing) ms"
        )
        settingsToggle(
          "Smart Turn",
          detail:
            "Wait for a complete thought before ending a turn. This controls timing, not text cleanup.",
          isOn: appState.settingsBinding(\.xaiSmartTurnEnabled))

        if appState.settings.xaiSmartTurnEnabled {
          settingsSlider(
            "Smart Turn threshold",
            value: appState.settingsBinding(\.xaiSmartTurnThreshold),
            in: 0...1,
            step: 0.05,
            valueLabel: appState.settings.xaiSmartTurnThreshold.formatted(
              .number.precision(.fractionLength(2)))
          )
          settingsStepper(
            "Smart Turn timeout",
            value: appState.settingsBinding(\.xaiSmartTurnTimeout),
            in: 1...5000,
            step: 100,
            valueLabel: "\(appState.settings.xaiSmartTurnTimeout) ms"
          )
        }
      }
    case .elevenLabs:
      settingsRow("Model") {
        Text(
          appState.settings.transcriptionMode == .realtime
            ? ElevenLabsTranscriptionContract.realtimeModelID
            : ElevenLabsTranscriptionContract.uploadModelID
        )
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      }

      settingsToggle(
        "Clean up spoken disfluencies",
        detail: "Use Scribe's non-verbatim mode for more readable speech.",
        isOn: appState.settingsBinding(\.elevenLabsNoVerbatim))

      if appState.settings.transcriptionMode == .realtime {
        settingsRow("Commit strategy") {
          Picker("Commit strategy", selection: appState.settingsBinding(\.elevenLabsCommitStrategy))
          {
            ForEach(ElevenLabsCommitStrategy.allCases) { strategy in
              Text(strategy.title).tag(strategy)
            }
          }
          .labelsHidden()
          .fixedSize()
        }

        if appState.settings.elevenLabsCommitStrategy == .vad {
          settingsStepper(
            "VAD silence",
            value: appState.settingsBinding(\.elevenLabsVADSilenceThreshold),
            in: 0.3...3,
            step: 0.1,
            valueLabel: String(format: "%.1f s", appState.settings.elevenLabsVADSilenceThreshold)
          )
          settingsSlider(
            "VAD threshold",
            value: appState.settingsBinding(\.elevenLabsVADThreshold),
            in: 0.1...0.9,
            step: 0.05,
            valueLabel: appState.settings.elevenLabsVADThreshold.formatted(
              .number.precision(.fractionLength(2)))
          )
          settingsStepper(
            "Minimum speech",
            value: appState.settingsBinding(\.elevenLabsMinSpeechDuration),
            in: 50...2000,
            step: 50,
            valueLabel: "\(appState.settings.elevenLabsMinSpeechDuration) ms"
          )
          settingsStepper(
            "Minimum silence",
            value: appState.settingsBinding(\.elevenLabsMinSilenceDuration),
            in: 50...2000,
            step: 50,
            valueLabel: "\(appState.settings.elevenLabsMinSilenceDuration) ms"
          )
        }
      }
    }
  }

  private var triggerStageSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      stageIntro("Set the global shortcut for dictation and focused-text polishing.")

      settingsGroup {
        VStack(spacing: 14) {
          KeyCap(text: appState.settings.hotkeyDisplay, prominence: .hero)
            .scaleEffect(isCapturingHotkey ? 1.06 : 1)

          Text(
            isCapturingHotkey
              ? "Press Fn/Globe or another shortcut. Press Escape to cancel."
              : ShortcutGestureInterpreter.summary
          )
          .font(.callout)
          .foregroundStyle(isCapturingHotkey ? VhraseTheme.accent : Color.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 460)
          .contentTransition(.interpolate)

          HStack(spacing: 10) {
            Button {
              appState.beginShortcutCapture()
              isCapturingHotkey = true
            } label: {
              Label(
                isCapturingHotkey ? "Listening" : "Change shortcut", systemImage: "record.circle")
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .settingsRowStyle()
        .animation(
          VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
          value: isCapturingHotkey
        )

        settingsRow("Shortcut", detail: "Choose a preset, or record any shortcut above.") {
          Picker("Shortcut", selection: appState.settingsBinding(\.hotkeyPreset)) {
            ForEach(appState.settings.availableHotkeyPresets) { preset in
              Text(preset.display).tag(preset)
            }
          }
          .labelsHidden()
          .fixedSize()
        }
      }
      .background {
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
      }
    }
  }

  private var listeningStageSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      stageIntro(
        "Choose your microphone, check its sound, and tell recognition which language to expect.")

      settingsGroup("Microphone", footer: inputDeviceError.isEmpty ? nil : inputDeviceError) {
        settingsRow("Input device", detail: "Applies to the preview below and to dictation.") {
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
          .frame(maxWidth: 260)
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

        switch appState.settings.provider {
        case .gemini:
          settingsRow(
            "Language hints",
            detail:
              "Optional BCP-47 codes separated by commas, such as en-US, yue-Hant-HK. Leave blank for automatic detection and code-switching."
          ) {
            TextField("Language hints", text: appState.settingsBinding(\.geminiLanguageHints))
              .textFieldStyle(.roundedBorder)
              .labelsHidden()
              .frame(width: 220)
          }
        case .parakeet:
          settingsRow(
            "Language",
            detail:
              "Parakeet detects the spoken language automatically among its 25 European languages, so no code is needed."
          ) {
            Text("Automatic")
              .foregroundStyle(.secondary)
          }
        case .xai, .elevenLabs:
          settingsRow(
            "Language",
            detail: appState.settings.provider == .xai
              ? "Grok detects spoken language automatically. This code enables number and currency formatting when that option is on, such as en."
              : "Use a language code such as en, yue, or zh. Leave blank for automatic detection."
          ) {
            TextField("Language", text: appState.settingsBinding(\.language))
              .textFieldStyle(.roundedBorder)
              .labelsHidden()
              .frame(width: 220)
          }
        }
      }

      settingsGroup("Microphone preview") {
        MicrophonePreviewView(
          preview: appState.audioInputPreview,
          settings: appState.settings,
          canPreview: appState.status.canStartRecording
        )
        .settingsRowStyle()
      }

      settingsGroup(
        "Processing",
        footer:
          "Applied locally to both upload and realtime audio. These controls never change speaker or headphone volume."
      ) {
        settingsToggle(
          "Automatic volume leveling",
          detail: "Gently evens out microphone loudness.",
          isOn: appState.settingsBinding(\.automaticVolumeLeveling))
        settingsSlider(
          "Volume adjustment",
          value: appState.settingsBinding(\.inputGainDB),
          in: -6...6,
          step: 1,
          valueLabel: "\(Int(appState.settings.inputGainDB)) dB"
        )
        settingsSlider(
          "Noise reduction",
          detail:
            "Reduces steady background noise. Values closer to zero preserve more of the original sound.",
          value: Binding(
            get: { -appState.settings.noiseReductionDB },
            set: { value in appState.updateSettings { $0.noiseReductionDB = -value } }
          ),
          in: -12...0,
          step: 1,
          valueLabel: appState.settings.noiseReductionDB == 0
            ? "0 dB" : "−\(Int(appState.settings.noiseReductionDB)) dB"
        )
      }

      Button {
        selectedTab = .system
        appState.refreshPermissions()
      } label: {
        Label("Review microphone access", systemImage: "arrow.up.right")
      }
      .buttonStyle(AccentLinkButtonStyle())
      .font(.callout)
    }
  }

  /// Refreshes attached microphones without replacing a saved choice when its device is disconnected.
  private func refreshInputDevices() {
    do {
      inputDevices = try AudioInputDevice.available()
      inputDeviceError = ""
    } catch {
      inputDeviceError = error.localizedDescription
    }
  }

  /// Maps each Capture setting to its one owning stage.
  private var capturePipelineNodes: [PipelineFlowNode] {
    let language = appState.settings.recognitionLanguage
    let keytermCount = appState.settings.keytermList.count
    return [
      PipelineFlowNode(
        id: .trigger,
        title: "Trigger",
        detail: appState.settings.hotkeyDisplay
      ),
      PipelineFlowNode(
        id: .listen,
        title: "Listen",
        detail: language.isEmpty ? "Auto language" : language
      ),
      PipelineFlowNode(
        id: .transcribe,
        title: "Transcribe",
        detail:
          "\(appState.settings.provider.title) · \(appState.settings.transcriptionModeTitle)",
        badge: keytermCount == 0 || appState.settings.provider == .parakeet
          ? nil
          : "\(keytermCount) preferred terms"
      ),
    ]
  }

  /// Routes Capture selection to one full stage editor.
  @ViewBuilder private var captureWorkflowStageEditor: some View {
    switch selectedCapturePipelineStage {
    case .trigger:
      triggerStageSettings
    case .listen:
      listeningStageSettings
    case .transcribe:
      transcriptionStageSettings
    }
  }

  private func cancelShortcutCaptureIfNeeded() {
    guard isCapturingHotkey else {
      return
    }
    isCapturingHotkey = false
    appState.cancelShortcutCapture()
  }
}
