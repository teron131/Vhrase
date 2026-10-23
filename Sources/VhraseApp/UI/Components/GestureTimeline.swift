// Draws the shortcut's key-press language shared by the Shortcut page's gesture tiles and Polishing's route thumbnails, so a gesture looks the same wherever it appears.

import SwiftUI

/// Draws a gesture over time: the line rises while the key is down, the band beneath marks when Vhrase records, and an optional mark shows the result.
struct GestureTimeline: View {
  let presses: [ClosedRange<CGFloat>]
  var recording: ClosedRange<CGFloat>?
  var outcome: String?
  var outcomeAt: CGFloat = 0

  static let doubleTap = GestureTimeline(
    presses: [0.06...0.15, 0.27...0.36], outcome: "wand.and.stars", outcomeAt: 0.62)

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack(alignment: .topLeading) {
        KeyPressLine(presses: presses)
          .stroke(
            Color.primary.opacity(0.7),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
          )
          .frame(height: 16)
        if let recording {
          Capsule()
            .fill(VhraseTheme.statusRecording)
            .frame(width: width * (recording.upperBound - recording.lowerBound), height: 6)
            .offset(x: width * recording.lowerBound, y: 24)
        }
        if let outcome {
          Image(systemName: outcome)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(VhraseTheme.accent)
            .frame(width: 18, height: 18)
            .offset(x: width * outcomeAt - 9, y: 0)
        }
      }
    }
    .frame(height: 30)
  }
}

private struct KeyPressLine: Shape {
  let presses: [ClosedRange<CGFloat>]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    for press in presses {
      let start = rect.minX + rect.width * press.lowerBound
      let end = rect.minX + rect.width * press.upperBound
      path.addLine(to: CGPoint(x: start, y: rect.maxY))
      path.addLine(to: CGPoint(x: start, y: rect.minY))
      path.addLine(to: CGPoint(x: end, y: rect.minY))
      path.addLine(to: CGPoint(x: end, y: rect.maxY))
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    return path
  }
}
