// Defines Vhrase's adaptive color, shape, spacing, and surface tokens.

import AppKit
import SwiftUI

enum VhraseTheme {
  static let accent = adaptiveColor(light: 0xE8431F, dark: 0xFF6242)
  static let accentSubtle = adaptiveColor(light: 0xE8431F, dark: 0xFF6242).opacity(0.14)
  static let canvas = adaptiveColor(light: 0xF7F4EF, dark: 0x161412)
  static let card = adaptiveColor(light: 0xFFFFFF, dark: 0x211E1B)
  static let field = Color.primary.opacity(0.055)
  static let hairline = Color.primary.opacity(0.11)
  static let inkSecondary = Color.secondary
  static let statusRecording = adaptiveColor(light: 0xD93A1E, dark: 0xFF5C3D)
  static let statusSuccess = adaptiveColor(light: 0x1F9D55, dark: 0x3ECF7A)
  static let statusWarning = adaptiveColor(light: 0xC77700, dark: 0xFFB224)
  static let statusFailure = adaptiveColor(light: 0xC62828, dark: 0xFF5147)
  static let statusProcessing = adaptiveColor(light: 0x7A5CFF, dark: 0x9D86FF)
  static let workflowAccent = adaptiveColor(light: 0x76567F, dark: 0xB88BC4)
  static let recorderBackground = Color.black
  static let recorderBorder = Color.white.opacity(0.18)

  static let heroCornerRadius: CGFloat = 16
  static let sectionCornerRadius: CGFloat = 12
  static let fieldCornerRadius: CGFloat = 9

  /// Maps a setup diagnostic's severity to its semantic status color across all surfaces.
  static func diagnosticColor(_ severity: SetupDiagnosticSeverity) -> Color {
    switch severity {
    case .ready:
      statusSuccess
    case .attention:
      statusWarning
    }
  }

  private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return nsColor(hex: match == .darkAqua ? dark : light)
      }
    )
  }

  private static func nsColor(hex: UInt32) -> NSColor {
    NSColor(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

private struct ContentSectionModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(20)
      .background(
        VhraseTheme.card,
        in: RoundedRectangle(cornerRadius: VhraseTheme.sectionCornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: VhraseTheme.sectionCornerRadius, style: .continuous)
          .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
      }
  }
}

private struct OperationalSurfaceModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(24)
      .background(
        VhraseTheme.card,
        in: RoundedRectangle(cornerRadius: VhraseTheme.heroCornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: VhraseTheme.heroCornerRadius, style: .continuous)
          .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
      }
  }
}

private struct InsetFieldModifier: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(
        VhraseTheme.field, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
      }
  }
}

extension View {
  func contentSection() -> some View {
    modifier(ContentSectionModifier())
  }

  func operationalSurface() -> some View {
    modifier(OperationalSurfaceModifier())
  }

  func insetField(cornerRadius: CGFloat = VhraseTheme.fieldCornerRadius) -> some View {
    modifier(InsetFieldModifier(cornerRadius: cornerRadius))
  }
}
