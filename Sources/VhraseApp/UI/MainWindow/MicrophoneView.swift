// Owns the microphone choice, its live check, and local processing; holds the preview microphone only while this destination's window is active.

import AVFoundation
import AppKit
import SwiftUI

struct MicrophoneView: View {
  @ObservedObject var appState: AppState
  @Environment(\.scenePhase) private var scenePhase
  @State private var inputDevices: [AudioInputDevice] = []
  @State private var inputDeviceError = ""
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Microphone",
        description: "Choose the microphone Vhrase listens to, then check how it sounds."
      )
      accessNotice
      deviceGroup
      settingsGroup("Live check") {
        MicrophonePreviewView(
          preview: appState.audioInputPreview,
          settings: appState.settings,
          canPreview: appState.canStartRecording
        )
        .settingsRowStyle()
      }
      processingGroup
    }
    .disabled(presentation.workflowControlsAreDisabled)
    .mainWindowEvents(
      appState: appState, onActivate: resumePreview,
      onDeactivate: { appState.audioInputPreview.stop() }
    )
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { refreshInputDevices() }
    }
    .onDisappear { appState.audioInputPreview.stop() }
  }

  /// A hidden window can become key without remounting this view or changing the app's scene phase.
  private func resumePreview() {
    guard appState.canStartRecording else { return }
    appState.audioInputPreview.start(settings: appState.settings)
  }

  @ViewBuilder private var accessNotice: some View {
    if let snapshot = presentation.permissions.snapshot(for: .microphone), !snapshot.state.isReady {
      NoticeCard(
        "Vhrase can't hear anything until macOS allows microphone access.",
        systemImage: "mic.slash",
        color: VhraseTheme.statusWarning,
        actionTitle: snapshot.actionTitle,
        action: { appState.handlePermissionAction(.microphone) }
      )
    }
  }

  private var deviceGroup: some View {
    settingsGroup(nil, footer: inputDeviceError.isEmpty ? nil : inputDeviceError) {
      settingsRow("Input device", detail: "Used for dictation and the live check below.") {
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
    }
  }

  private var processingGroup: some View {
    settingsGroup(
      "Processing",
      footer:
        "Applied on this Mac to both upload and realtime audio. These controls never change speaker or headphone volume."
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
}
