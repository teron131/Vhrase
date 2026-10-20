// Draws Vhrase's shared parrot mark, the lavender parrot in a laser visor, for the menu bar and branded in-app surfaces; the art matches Resources/VhraseAppIcon.svg.

import AppKit
import SwiftUI

struct ParrotMark: View {
  /// Supplies a native image to the status item, preserving transparent cutouts and system contrast.
  /// In one color the visor merges with the head, so its scanline is cut out to keep the glasses readable.
  static let menuBarImage: NSImage = {
    let size = NSSize(width: 18, height: 18)
    let bounds = CGRect(origin: .zero, size: size)
    let image = NSImage(size: size, flipped: true) { _ in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.setFillColor(NSColor.black.cgColor)
      context.addPath(ParrotBody().path(in: bounds).cgPath)
      context.drawPath(using: .eoFill)
      context.addPath(ParrotVisor().path(in: bounds).cgPath)
      context.fillPath()
      context.setBlendMode(.clear)
      context.addPath(ParrotScanline(width: 1.1).path(in: bounds).cgPath)
      context.fillPath()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Vhrase"
    return image
  }()

  private static let lavenderLight = Color(hex: 0xE3D9ED)
  private static let lavender = Color(hex: 0xC5ACD3)
  private static let lavenderDeep = Color(hex: 0xA77DB8)
  private static let faceMask = Color(hex: 0xF6F2FA)
  private static let violet = Color(hex: 0x9D86FF)
  private static let flight = Color(hex: 0x7A5CFF)
  private static let flightTip = Color(hex: 0x4F38C2)
  private static let billRidge = Color(hex: 0xF3EEF7)
  private static let bill = Color(hex: 0xAB97BF)
  private static let glass = Color(hex: 0x170F1D)
  private static let laser = Color(hex: 0xFF6242)
  private static let glow = Color(hex: 0xB88BC4)

  /// Paints the plumage zones in artwork coordinates, as the icon's SVG does, so both stay in step.
  var body: some View {
    Canvas { context, size in
      let bounds = CGRect(origin: .zero, size: size)
      let art = artworkTransform(in: bounds)
      func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(art) }
      let everywhere = Path(bounds)

      context.drawLayer { bird in
        bird.clip(to: ParrotBody().path(in: bounds), style: FillStyle(eoFill: true))
        bird.fill(
          everywhere,
          with: .linearGradient(
            Gradient(colors: [Self.lavenderLight, Self.lavender, Self.lavenderDeep]),
            startPoint: point(16, 3.5), endPoint: point(16, 29.2)))
        bird.fill(
          everywhere,
          with: .radialGradient(
            Gradient(colors: [
              Self.faceMask.opacity(0.85), Self.faceMask.opacity(0.45), Self.faceMask.opacity(0),
            ]),
            center: point(23.6, 7.4), startRadius: 0, endRadius: 4.4 * art.a))
        bird.drawLayer { wing in
          wing.clip(to: ParrotWing().path(in: bounds))
          wing.fill(ArtPolygon.violetBand.path(in: bounds), with: .color(Self.violet))
          wing.fill(
            ArtPolygon.flightBand.path(in: bounds),
            with: .linearGradient(
              Gradient(colors: [Self.flight, Self.flightTip]), startPoint: point(15, 16),
              endPoint: point(7.8, 23.3)))
        }
        bird.fill(
          ArtPolygon.tail.path(in: bounds),
          with: .linearGradient(
            Gradient(stops: [
              .init(color: Self.lavenderDeep, location: 0),
              .init(color: Self.lavenderDeep, location: 0.45),
              .init(color: Self.flight, location: 1),
            ]),
            startPoint: point(12.5, 24.5), endPoint: point(3.5, 29)))
        bird.fill(
          ParrotBill().path(in: bounds),
          with: .linearGradient(
            Gradient(colors: [Self.billRidge, Self.bill]), startPoint: point(27, 6),
            endPoint: point(28.5, 13)))
      }
      context.fill(ParrotVisor().path(in: bounds), with: .color(Self.glass))
      context.fill(ParrotScanline(width: 0.6).path(in: bounds), with: .color(Self.laser))
    }
    .shadow(color: Self.glow.opacity(0.2), radius: 4)
  }
}

/// Maps the approved 32-unit artwork into the available bounds, including zero-size layouts.
private func artworkTransform(in rect: CGRect) -> CGAffineTransform {
  let scale = min(rect.width, rect.height) / 32
  return CGAffineTransform(
    a: scale, b: 0, c: 0, d: scale,
    tx: rect.midX - 16 * scale,
    ty: rect.midY - 16 * scale
  )
}

/// The parrot silhouette with its wing slit, which needs an even-odd fill.
private struct ParrotBody: Shape {
  func path(in rect: CGRect) -> Path {
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

    return path.applying(artworkTransform(in: rect))
  }
}

/// A wraparound visor at eye level: a strap at the back of the head widens into the lens, whose tip juts past the forehead.
private struct ParrotVisor: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 18.6, y: 6.25))
    path.addLine(to: CGPoint(x: 28.75, y: 5.25))
    path.addLine(to: CGPoint(x: 27.95, y: 7.7))
    path.addCurve(
      to: CGPoint(x: 25.1, y: 8.38),
      control1: CGPoint(x: 26.9, y: 8.05),
      control2: CGPoint(x: 26, y: 8.3)
    )
    path.addCurve(
      to: CGPoint(x: 21.3, y: 7.42),
      control1: CGPoint(x: 23.6, y: 8.5),
      control2: CGPoint(x: 22.3, y: 7.7)
    )
    path.addLine(to: CGPoint(x: 18.15, y: 7.1))
    path.closeSubpath()
    return path.applying(artworkTransform(in: rect))
  }
}

/// The visor's laser line, as a filled outline so it scales with the mark; `width` is in artwork units.
private struct ParrotScanline: Shape {
  let width: CGFloat

  func path(in rect: CGRect) -> Path {
    var line = Path()
    line.move(to: CGPoint(x: 21.7, y: 6.74))
    line.addLine(to: CGPoint(x: 27.85, y: 6.29))
    return line.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round))
      .applying(artworkTransform(in: rect))
  }
}

/// Everything between the back outline and the wing slit, overdrawn past the body so the body clip trims it.
private struct ParrotWing: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 21.2, y: 10.6))
    path.addLine(to: CGPoint(x: 19.6, y: 12.8))
    path.addCurve(
      to: CGPoint(x: 9.9, y: 22.3),
      control1: CGPoint(x: 18.6, y: 16.8),
      control2: CGPoint(x: 14.4, y: 19.6)
    )
    path.addLine(to: CGPoint(x: 6.8, y: 22.9))
    path.addLine(to: CGPoint(x: 2.5, y: 21.5))
    path.addLine(to: CGPoint(x: 12.5, y: 9))
    path.addLine(to: CGPoint(x: 17.8, y: 6.9))
    path.closeSubpath()
    return path.applying(artworkTransform(in: rect))
  }
}

/// The upper mandible and hook, closed along the feather line under the visor.
private struct ParrotBill: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 26.7, y: 6.1))
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
      to: CGPoint(x: 26.7, y: 6.1),
      control1: CGPoint(x: 25.9, y: 8),
      control2: CGPoint(x: 26.2, y: 6.9)
    )
    path.closeSubpath()
    return path.applying(artworkTransform(in: rect))
  }
}

/// Straight-edged plumage zones; the body's own lavender serves as the wing coverts, and the icon's scalloped feather tips are too small to see at in-app sizes.
private struct ArtPolygon: Shape {
  let corners: [CGPoint]

  static let violetBand = ArtPolygon(corners: [
    CGPoint(x: 13.04, y: 11.64), CGPoint(x: 9.76, y: 15.23), CGPoint(x: 15.67, y: 20.62),
    CGPoint(x: 18.94, y: 17.04),
  ])
  static let flightBand = ArtPolygon(corners: [
    CGPoint(x: 9.76, y: 15.23), CGPoint(x: 0.17, y: 25.72), CGPoint(x: 6.07, y: 31.12),
    CGPoint(x: 15.67, y: 20.62),
  ])
  static let tail = ArtPolygon(corners: [
    CGPoint(x: 13.7, y: 23.9), CGPoint(x: 12.8, y: 26), CGPoint(x: 2, y: 30.5),
    CGPoint(x: 1.5, y: 27), CGPoint(x: 6.8, y: 22.9), CGPoint(x: 9.9, y: 22.3),
  ])

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addLines(corners)
    path.closeSubpath()
    return path.applying(artworkTransform(in: rect))
  }
}

extension Color {
  fileprivate init(hex: UInt32) {
    self.init(
      red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}
