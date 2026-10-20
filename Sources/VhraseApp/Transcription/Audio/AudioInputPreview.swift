// Owns the settings-only microphone preview and prevents stale startup work from competing with dictation.

import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioInputPreview: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published private(set) var level = 0.0
  @Published private(set) var inputLevel = 0.0
  @Published private(set) var waveformHistory: [Double] = []
  @Published private(set) var inputWaveformHistory: [Double] = []
  @Published private(set) var isListening = false
  @Published private(set) var isStarting = false
  @Published private(set) var errorMessage = ""
  @Published private(set) var isRecordingTest = false
  @Published private(set) var isPlayingTest = false
  @Published private(set) var testClip = AudioTestClip()

  private var recorder: AudioRecorder?
  private var startup: Task<Void, Never>?
  private var sessionID: UUID?
  private var player: AVAudioPlayer?
  private var playbackSettings: DictationSettings?
  private var testDeadline: Task<Void, Never>?
  private var inputDeviceUID = ""
  private var waveformTick = 0

  /// Updates running capture in place; only initial startup needs to acquire the microphone.
  func start(settings: DictationSettings) {
    if let recorder, recorder.isRecording, !isPlayingTest, inputDeviceUID == settings.inputDeviceUID
    {
      do {
        try recorder.updatePreview(settings: settings)
        discardTest()
        errorMessage = ""
      } catch {
        errorMessage = error.localizedDescription
      }
      return
    }
    restart(settings: settings)
  }

  /// Explicit tab presses reacquire the microphone even when an interrupted engine still reports itself running.
  func restart(settings: DictationSettings) {
    stop()
    startCapture(settings: settings)
  }

  private func startCapture(settings: DictationSettings) {
    stopCapture()
    inputDeviceUID = settings.inputDeviceUID
    errorMessage = ""
    isStarting = true
    let id = UUID()
    sessionID = id
    let recorder = AudioRecorder()
    self.recorder = recorder
    startup = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(180))
        try await recorder.startPreview(settings: settings) { [weak self] chunk in
          Task { @MainActor [weak self] in
            self?.receive(chunk, sessionID: id)
          }
        } onFailure: { [weak self] error in
          guard let self, self.sessionID == id else { return }
          self.stop()
          self.errorMessage = error.localizedDescription
        }
        guard let self, self.sessionID == id else {
          recorder.cancel()
          return
        }
        self.isStarting = false
        self.startup = nil
      } catch {
        recorder.cancel()
        guard let self, self.sessionID == id else { return }
        self.isStarting = false
        self.startup = nil
        self.recorder = nil
        if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
      }
    }
  }

  private func receive(_ chunk: AudioChunk, sessionID id: UUID) {
    guard sessionID == id else { return }
    // Smooth only the display; captured samples and playback retain their original timing and level.
    level += (chunk.level - level) * 0.3
    inputLevel += (chunk.inputLevel - inputLevel) * 0.3
    waveformTick += 1
    if waveformTick >= 3 {
      waveformTick = 0
      waveformHistory.append(chunk.level)
      inputWaveformHistory.append(chunk.inputLevel)
      if waveformHistory.count > 24 {
        waveformHistory.removeFirst(waveformHistory.count - 24)
        inputWaveformHistory.removeFirst(inputWaveformHistory.count - 24)
      }
    }
    if !isListening { isListening = true }
    if isRecordingTest {
      testClip.append(chunk.data)
      if testClip.isComplete {
        isRecordingTest = false
        testDeadline?.cancel()
        testDeadline = nil
      }
    }
  }

  /// Also discards any recorded test clip.
  func stop() {
    stopCapture()
    discardTest()
    clearPlayback()
  }

  /// Captures a bounded sample only after the user requests a test; ordinary metering retains no clip.
  func recordTest() {
    guard isListening, !isPlayingTest else { return }
    discardTest()
    errorMessage = ""
    isRecordingTest = true
    testDeadline = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(7)) } catch { return }
      guard let self, self.isRecordingTest else { return }
      self.isRecordingTest = false
      self.errorMessage = "The microphone stopped sending audio. Try recording the test again."
    }
  }

  /// Plays the processed test at the existing system volume, with microphone capture suspended to prevent feedback.
  func playTest(settings: DictationSettings) {
    guard !testClip.isEmpty, !isRecordingTest else { return }
    stopCapture()
    do {
      let player = try AVAudioPlayer(data: testClip.wavData)
      player.delegate = self
      guard player.play() else {
        startCapture(settings: settings)
        errorMessage = "Could not play the microphone test."
        return
      }
      self.player = player
      playbackSettings = settings
      isPlayingTest = true
    } catch {
      startCapture(settings: settings)
      errorMessage = error.localizedDescription
    }
  }

  func stopPlayback(settings: DictationSettings) {
    clearPlayback()
    startCapture(settings: settings)
  }

  private func clearPlayback() {
    playbackSettings = nil
    player?.stop()
    player = nil
    isPlayingTest = false
  }

  private func discardTest() {
    testDeadline?.cancel()
    testDeadline = nil
    isRecordingTest = false
    testClip = AudioTestClip()
  }

  /// Resumes capture only for the player that actually finished, never a stale playback callback.
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    let identity = ObjectIdentifier(player)
    Task { @MainActor [weak self] in
      guard let self, let currentPlayer = self.player,
        ObjectIdentifier(currentPlayer) == identity, let settings = self.playbackSettings
      else { return }
      self.stopPlayback(settings: settings)
      if !flag { self.errorMessage = "The microphone test could not finish playing." }
    }
  }

  private func stopCapture() {
    sessionID = nil
    startup?.cancel()
    startup = nil
    recorder?.cancel()
    recorder = nil
    level = 0
    inputLevel = 0
    waveformHistory = []
    inputWaveformHistory = []
    waveformTick = 0
    isListening = false
    isStarting = false
  }
}
