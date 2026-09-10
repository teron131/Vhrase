// Draws Vhrase's shared parrot mark for the menu bar and branded in-app surfaces.

import AppKit
import SwiftUI

struct ParrotMark: View {
  /// Supplies a native image to the status item, preserving transparent cutouts and system contrast.
  static let menuBarImage: NSImage = {
    let size = NSSize(width: 18, height: 18)
    let path = ParrotSilhouette().path(in: CGRect(origin: .zero, size: size)).cgPath
    let image = NSImage(size: size, flipped: true) { _ in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.setFillColor(NSColor.black.cgColor)
      context.addPath(path)
      context.drawPath(using: .eoFill)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Vhrase"
    return image
  }()

  var body: some View {
    ParrotSilhouette()
      .fill(birdGradient, style: FillStyle(eoFill: true))
      .shadow(color: Color(red: 184 / 255, green: 139 / 255, blue: 196 / 255).opacity(0.2), radius: 4)
  }

  private var birdGradient: LinearGradient {
    LinearGradient(
      stops: [
        .init(color: Color(red: 227 / 255, green: 217 / 255, blue: 237 / 255), location: 0),
        .init(color: Color(red: 197 / 255, green: 172 / 255, blue: 211 / 255), location: 0.5),
        .init(color: Color(red: 167 / 255, green: 125 / 255, blue: 184 / 255), location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
  }
}

private struct ParrotSilhouette: Shape {
  /// Maps the approved 32-unit artwork into the available bounds, including zero-size layouts.
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 32
    let transform = CGAffineTransform(
      a: scale, b: 0, c: 0, d: scale,
      tx: rect.midX - 16 * scale,
      ty: rect.midY - 16 * scale
    )

    var path = Path()
    path.move(to: CGPoint(x: 3.2, y: 29.2))
    path.addLine(to: CGPoint(x: 8.5, y: 22.2))
    path.addLine(to: CGPoint(x: 6.8, y: 22.9))
    path.addCurve(
      to: CGPoint(x: 14.7, y: 11.8),
      control1: CGPoint(x: 9.5, y: 19.4),
      control2: CGPoint(x: 11.4, y: 15.2)
    )
    path.addCurve(
      to: CGPoint(x: 19.7, y: 5),
      control1: CGPoint(x: 16.9, y: 9.5),
      control2: CGPoint(x: 17.6, y: 6.8)
    )
    path.addCurve(
      to: CGPoint(x: 25.5, y: 4.1),
      control1: CGPoint(x: 21.3, y: 3.6),
      control2: CGPoint(x: 23.8, y: 3.3)
    )
    path.addCurve(
      to: CGPoint(x: 26.7, y: 6.1),
      control1: CGPoint(x: 26.2, y: 4.5),
      control2: CGPoint(x: 26.6, y: 5.2)
    )
    path.addCurve(
      to: CGPoint(x: 29, y: 11.5),
      control1: CGPoint(x: 29, y: 6.8),
      control2: CGPoint(x: 30, y: 9.3)
    )
    path.addCurve(
      to: CGPoint(x: 27.3, y: 13.2),
      control1: CGPoint(x: 28.6, y: 12.3),
      control2: CGPoint(x: 27.9, y: 12.9)
    )
    path.addCurve(
      to: CGPoint(x: 25.8, y: 9.1),
      control1: CGPoint(x: 27.9, y: 11.1),
      control2: CGPoint(x: 27.3, y: 9.7)
    )
    path.addCurve(
      to: CGPoint(x: 24.2, y: 13.4),
      control1: CGPoint(x: 24.2, y: 10),
      control2: CGPoint(x: 24.2, y: 11.8)
    )
    path.addCurve(
      to: CGPoint(x: 18, y: 23.2),
      control1: CGPoint(x: 24.2, y: 17.7),
      control2: CGPoint(x: 21.9, y: 21.3)
    )
    path.addLine(to: CGPoint(x: 12.8, y: 26))
    path.addLine(to: CGPoint(x: 13.7, y: 23.9))
    path.addLine(to: CGPoint(x: 3.2, y: 29.2))
    path.closeSubpath()

    path.move(to: CGPoint(x: 18.9, y: 7.55))
    path.addLine(to: CGPoint(x: 20.2, y: 6.2))
    path.addLine(to: CGPoint(x: 25, y: 5.5))
    path.addLine(to: CGPoint(x: 26.2, y: 6.1))
    path.addLine(to: CGPoint(x: 24.5, y: 8.8))
    path.addLine(to: CGPoint(x: 20.8, y: 8.9))
    path.addLine(to: CGPoint(x: 19.7, y: 7.55))
    path.addLine(to: CGPoint(x: 18.9, y: 7.55))
    path.closeSubpath()

    path.move(to: CGPoint(x: 19.6, y: 12.8))
    path.addCurve(
      to: CGPoint(x: 9.9, y: 22.3),
      control1: CGPoint(x: 18.6, y: 16.8),
      control2: CGPoint(x: 14.4, y: 19.6)
    )
    path.addCurve(
      to: CGPoint(x: 19.6, y: 12.8),
      control1: CGPoint(x: 14.1, y: 18.5),
      control2: CGPoint(x: 17.1, y: 16)
    )
    path.closeSubpath()

    return path.applying(transform)
  }
}
