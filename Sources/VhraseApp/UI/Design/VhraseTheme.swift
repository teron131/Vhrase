// Defines Vhrase's color, shape, and surface tokens; color encodes identity or workflow state, never decoration.

import AppKit
import SwiftUI

enum VhraseTheme {
  /// The accent and processing violet deliberately keep one color in both appearances, so the UI looks the same in light and dark.
  static let accent = color(0xFF6242)
  static let canvas = adaptiveColor(light: 0xF7F4EF, dark: 0x161412)
  static let card = adaptiveColor(light: 0xFFFFFF, dark: 0x211E1B)
  static let field = Color.primary.opacity(0.055)
  static let hairline = Color.primary.opacity(0.11)
  static let inkSecondary = Color.secondary
  static let statusRecording = adaptiveColor(light: 0xD93A1E, dark: 0xFF5C3D)
  static let statusSuccess = adaptiveColor(light: 0x1F9D55, dark: 0x3ECF7A)
  static let statusWarning = adaptiveColor(light: 0xC77700, dark: 0xFFB224)
  static let statusFailure = adaptiveColor(light: 0xC62828, dark: 0xFF5147)
  static let statusProcessing = color(0x9D86FF)
  static let recorderBackground = Color.black
  static let recorderBorder = Color.white.opacity(0.18)

  /// Generous, soft corners carry the playful shape language; the mic bar is roundest and fields step down from groups.
  static let sheetCornerRadius: CGFloat = 24
  static let groupCornerRadius: CGFloat = 16
  static let fieldCornerRadius: CGFloat = 10

  /// Maps a setup diagnostic's severity to its semantic status color across all surfaces.
  static func diagnosticColor(_ severity: SetupDiagnosticSeverity) -> Color {
    switch severity {
    case .ready:
      statusSuccess
    case .attention:
      statusWarning
    }
  }

  private static func color(_ hex: UInt32) -> Color {
    Color(nsColor: nsColor(hex: hex))
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

/// Gives action links the app accent instead of AppKit's system-blue link treatment.
struct AccentLinkButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(
        isEnabled
          ? (configuration.role == .destructive ? VhraseTheme.statusFailure : VhraseTheme.accent)
          : Color.secondary
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
      .contentShape(Rectangle())
      .accessibilityAddTraits(.isLink)
  }
}

private struct SurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(
        VhraseTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
  /// Places content on a raised card with a hairline edge and no shadow; callers own the inner padding.
  func surface(cornerRadius: CGFloat = VhraseTheme.groupCornerRadius) -> some View {
    modifier(SurfaceModifier(cornerRadius: cornerRadius))
  }

  func insetField(cornerRadius: CGFloat = VhraseTheme.fieldCornerRadius) -> some View {
    modifier(InsetFieldModifier(cornerRadius: cornerRadius))
  }
}
