// Draws the recorder pill's microphone level as a waveform that enters on the right and streams left.

import SwiftUI

/// Adds one bar per step on the right and glides older bars left at a constant speed, so speech streams across the pill.
/// Bars grow in over the rightmost slot and shrink away over the leftmost, so nothing pops at either end.
/// Bar height is proportional to level relative to the loudest recent bar, so speech stands tall on a quiet microphone; the Listen preview remains the absolute meter.
/// Sound far below that level counts as background and stays a dot, and a stream with only background rests as a still row of dots.
struct RecorderWaveform: View {
  /// Bars at full size between the two edge slots; with them the waveform spans most of the recorder pill.
  private static let barCount = 21
  private static let barWidth: CGFloat = 4
  private static let spacing: CGFloat = 3
  private static let slotWidth = barWidth + spacing
  /// Half the pill's height, so the tallest bar keeps a quarter of the pill clear above and below it.
  private static let height: CGFloat = 26
  /// How often a 100 ms audio chunk replaces the level.
  private static let chunkInterval = 0.1
  /// Two chunks per bar, which moves the stream at 35 points per second.
  private static let stepInterval = 2 * chunkInterval
  /// The quietest level that can fill the pill; quieter speech is drawn in proportion so room noise is never stretched to full height.
  private static let quietestPeak = 0.12
  /// The share of the recent peak below which sound counts as background.
  private static let backgroundShare = 0.15
  /// Per-step decay that halves the remembered peak in about 3.4 seconds.
  private static let peakDecay = 0.96

  /// The latest processed microphone level, from 0 to 1.
  let level: Double

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Bar levels from oldest to newest; the first is leaving through the left edge slot.
  @State private var history = [Double](repeating: 0, count: barCount + 1)
  /// The level read halfway through the current step, covering the first of a bar's two audio chunks.
  @State private var earlierLevel: Double?
  /// The loudest recent audible level, which new bars are scaled against.
  @State private var peak = quietestPeak
  /// When the newest bar started entering; the stream glides one bar slot per step from then.
  @State private var stepStart = Date.distantPast

  var body: some View {
    TimelineView(.animation(minimumInterval: reduceMotion ? Self.chunkInterval : nil)) { timeline in
      let slide = remainingSlide(at: timeline.date)
      HStack(spacing: Self.spacing) {
        ForEach(history.indices, id: \.self) { index in
          bar(level: history[index], slot: Double(index) + slide)
        }
      }
      .offset(x: slide * Self.slotWidth)
      .frame(
        width: CGFloat(Self.barCount + 2) * Self.slotWidth - Self.spacing,
        height: Self.height,
        alignment: .leading
      )
      .onChange(of: timeline.date) { _, date in step(at: date) }
    }
  }

  /// Rests as a dot and grows to the full waveform height at the loudest recent level, shrinking and fading while it crosses an edge slot.
  private func bar(level: Double, slot: Double) -> some View {
    // Full between the edge slots, falling to nothing at the outer end of either one.
    let presence = min(1, max(0, min(slot, Double(Self.barCount + 1) - slot)))
    return Capsule()
      .frame(
        width: Self.barWidth,
        height: Self.barWidth + (Self.height - Self.barWidth) * level * presence
      )
      .opacity((0.4 + 0.6 * level) * presence)
  }

  /// The share of a slot the stream still has to slide left to finish the current step; Reduce Motion moves it in whole slots.
  private func remainingSlide(at date: Date) -> Double {
    guard !reduceMotion else {
      return 0
    }
    return 1 - min(1, max(0, date.timeIntervalSince(stepStart) / Self.stepInterval))
  }

  /// Admits the louder of the step's two chunk readings as the newest bar once the previous bar has finished entering.
  private func step(at date: Date) {
    let sinceStep = date.timeIntervalSince(stepStart)
    guard sinceStep >= Self.stepInterval else {
      if sinceStep >= Self.chunkInterval, earlierLevel == nil {
        earlierLevel = level
      }
      return
    }
    let audible = WaveformLevelResponse.audibleLevel(max(earlierLevel ?? 0, level))
    let loudestRecent = max(audible, peak * Self.peakDecay, Self.quietestPeak)
    let barLevel =
      max(0, audible / loudestRecent - Self.backgroundShare) / (1 - Self.backgroundShare)
    // With nothing above the background on screen or arriving, the stream stays put.
    guard barLevel > 0 || history.contains(where: { $0 > 0 }) else {
      return
    }

    earlierLevel = nil
    peak = loudestRecent
    history.removeFirst()
    history.append(barLevel)
    // Consecutive steps stay on one clock for a constant glide speed; the first step after a rest starts a new one.
    stepStart =
      sinceStep < 2 * Self.stepInterval ? stepStart.addingTimeInterval(Self.stepInterval) : date
  }
}
