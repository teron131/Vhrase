// Publishes what changes continuously while a dictation records, its microphone level and elapsed time, apart from AppState so those updates redraw only the views that show them.

import Combine
import Foundation

/// Holds the active recording's latest level, a decimated history for waveforms, and its running time.
///
/// Views observe it directly: an AppState change re-evaluates every window, which ten level updates a second would repeat even while the main window is hidden.
@MainActor
final class RecordingMeter: ObservableObject {
  /// Enough bars for Dictate's full-width signal line; smaller surfaces read their own suffix.
  private static let historyLimit = 96
  /// Audio arrives in 100 ms chunks; every third one becomes a waveform bar.
  private static let chunksPerBar = 3

  /// The latest processed microphone level, from 0 to 1.
  @Published private(set) var level = 0.0
  @Published private(set) var waveformHistory: [Double] = []
  @Published private(set) var elapsedSeconds = 0
  private var chunksSinceBar = 0
  private var clock: Timer?

  var elapsedTime: String {
    String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
  }

  /// Counts whole seconds from the moment the microphone is running.
  func startClock() {
    clock?.invalidate()
    let startedAt = Date()
    clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        let elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
        guard elapsedSeconds != self.elapsedSeconds else {
          return
        }
        self.elapsedSeconds = elapsedSeconds
      }
    }
  }

  func record(_ level: Double) {
    self.level = level
    chunksSinceBar += 1
    guard chunksSinceBar >= Self.chunksPerBar else { return }
    chunksSinceBar = 0
    waveformHistory.append(level)
    if waveformHistory.count > Self.historyLimit {
      waveformHistory.removeFirst(waveformHistory.count - Self.historyLimit)
    }
  }

  /// Stops the clock and returns to rest between recordings, without republishing values that already rest.
  func reset() {
    clock?.invalidate()
    clock = nil
    chunksSinceBar = 0
    if level != 0 { level = 0 }
    if !waveformHistory.isEmpty { waveformHistory = [] }
    if elapsedSeconds != 0 { elapsedSeconds = 0 }
  }
}
