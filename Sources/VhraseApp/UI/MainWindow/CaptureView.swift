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
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        pageHeader(
          MainWindowTab.capture.title,
          description: "Choose how Vhrase listens and which shortcut follows you across apps.",
          systemImage: MainWindowTab.capture.systemImage
        )

        workflowEditor(
          "Transcription workflow",
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

  private var transcriptionStageSettings: some View {
    VStack(alignment: .leading, spacing: 14) {
      workflowStageHeader(
        "Transcribe",
        description: "Choose the speech service and tune how it recognizes your words.",
        systemImage: "waveform"
      )

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
        GridRow {
          Text("Provider")
            .gridColumnAlignment(.trailing)
          ProviderPicker(selection: appState.settingsBinding(\.provider), style: .segmented)
            .fixedSize()
            .gridColumnAlignment(.leading)
        }

        GridRow {
          Text("Mode")
          TranscriptionModePicker(
            selection: appState.settingsBinding(\.transcriptionMode),
            enabledModes: appState.settings.provider.availableModes
          )
          .fixedSize()
        }
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

      VocabularyEditor(appState: appState)
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

  private var triggerStageSettings: some View {
    VStack(alignment: .leading, spacing: 14) {
      workflowStageHeader(
        "Trigger",
        description: "Set the global shortcut for dictation and focused-text polishing.",
        systemImage: "keyboard"
      )

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

    }
  }

  private var listeningStageSettings: some View {
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

  /// Refreshes attached microphones without replacing a saved choice when its device is disconnected.
  private func refreshInputDevices() {
    do {
      inputDevices = try AudioInputDevice.available()
      inputDeviceError = ""
    } catch {
      inputDeviceError = error.localizedDescription
    }
  }

  /// Keeps workflow navigation and its sole editor in one open, divider-led composition.
  private func workflowEditor<Editor: View>(
    _ title: String,
    description: String,
    nodes: [PipelineFlowNode],
    selection: Binding<PipelineStage>,
    @ViewBuilder editor: () -> Editor
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(description)
          .font(.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
      }

      HStack(alignment: .top, spacing: 0) {
        PipelineFlowView(nodes: nodes, selection: selection)
          .frame(width: 242)
          .padding(.trailing, 24)
          .padding(.vertical, 18)

        Divider()

        editor()
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.leading, 32)
          .padding(.vertical, 18)
          .id(selection.wrappedValue)
          .transition(.opacity.combined(with: .move(edge: .trailing)))
      }
      .overlay(alignment: .top) {
        Divider()
      }
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
        value: selection.wrappedValue
      )
    }
  }

  /// Maps each Capture setting to its one owning stage.
  private var capturePipelineNodes: [PipelineFlowNode] {
    let language = appState.settings.recognitionLanguage
    let keytermCount = appState.settings.keytermList.count
    return [
      PipelineFlowNode(
        id: .trigger,
        systemImage: "keyboard",
        title: "Trigger",
        detail: appState.settings.hotkeyDisplay
      ),
      PipelineFlowNode(
        id: .listen,
        systemImage: "mic.fill",
        title: "Listen",
        detail: language.isEmpty ? "Auto language" : language
      ),
      PipelineFlowNode(
        id: .transcribe,
        systemImage: "waveform",
        title: "Transcribe",
        detail:
          "\(appState.settings.provider.title) · \(appState.settings.transcriptionMode.title)",
        badge: keytermCount == 0
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
