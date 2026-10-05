// Keeps the settings waveform live only while its window is active and dictation does not own the microphone.

import SwiftUI

struct MicrophonePreviewView: View {
  @ObservedObject var preview: AudioInputPreview
  let settings: DictationSettings
  let canPreview: Bool

  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(statusText)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 20) {
        levelMeter(
          "Microphone input", level: preview.inputLevel, history: preview.inputWaveformHistory)
        levelMeter("After processing", level: preview.level, history: preview.waveformHistory)
      }

      HStack(spacing: 12) {
        Button(preview.isRecordingTest ? "Recording test…" : "Record 5-second test") {
          preview.recordTest()
        }
        .disabled(!preview.isListening || preview.isRecordingTest || preview.isPlayingTest)

        if preview.isPlayingTest {
          Button("Stop playback") { preview.stopPlayback(settings: settings) }
        } else {
          Button("Play test") { preview.playTest(settings: settings) }
            .disabled(preview.testClip.isEmpty || preview.isRecordingTest || !isEnabled)
        }
      }
      .buttonStyle(.bordered)

      if !preview.errorMessage.isEmpty {
        HStack(alignment: .top) {
          Text(preview.errorMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Try again") { preview.restart(settings: settings) }
            .disabled(!isEnabled)
        }
      } else {
        Text(
          "Watch your microphone while adjusting the controls below. Record a short test, then play it to hear the processing. Test audio stays in memory and is discarded when you leave this panel."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .task(
      id: Request(
        inputDeviceUID: settings.inputDeviceUID,
        automaticVolumeLeveling: settings.automaticVolumeLeveling,
        inputGainDB: settings.inputGainDB,
        noiseReductionDB: settings.noiseReductionDB,
        isEnabled: isEnabled
      )
    ) {
      if isEnabled {
        preview.start(settings: settings)
      } else {
        preview.stop()
      }
    }
    .onDisappear { preview.stop() }
  }

  private var isEnabled: Bool {
    canPreview && scenePhase == .active
  }

  private var statusText: String {
    if !canPreview { return "Paused during dictation" }
    if !isEnabled { return "Paused" }
    if !preview.errorMessage.isEmpty { return "Microphone unavailable" }
    if preview.isPlayingTest { return "Playing microphone test" }
    if preview.isRecordingTest { return "Recording 5-second test" }
    if preview.isStarting { return "Starting…" }
    return preview.isListening ? "Live · not recording" : "Waiting for microphone…"
  }

  private func levelMeter(_ title: String, level: Double, history: [Double]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      WaveformView(
        history: history,
        response: .live,
        tint: VhraseTheme.accent,
        height: 112
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(level < 0.02 ? "Quiet" : level < 0.4 ? "Moderate" : "Loud")
  }

  private struct Request: Equatable {
    let inputDeviceUID: String
    let automaticVolumeLeveling: Bool
    let inputGainDB: Double
    let noiseReductionDB: Double
    let isEnabled: Bool
  }
}
