// Renders compact semantic status labels and keyboard shortcut caps across Vhrase.

import SwiftUI

struct StatusPill: View {
  let title: String
  let systemImage: String
  let color: Color

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(VhraseFont.micro)
      .foregroundStyle(color)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(color.opacity(0.12), in: Capsule())
      .accessibilityElement(children: .combine)
  }
}

/// Renders a keyboard shortcut as a physical key cap.
struct KeyCap: View {
  enum Prominence {
    case compact
    case hero
  }

  let text: String
  var prominence: Prominence = .compact

  var body: some View {
    Text(text)
      .font(prominence == .hero ? VhraseFont.timer.monospaced() : VhraseFont.micro.monospaced())
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, prominence == .hero ? 20 : 8)
      .padding(.vertical, prominence == .hero ? 12 : 4)
      .background(
        VhraseTheme.field,
        in: RoundedRectangle(cornerRadius: prominence == .hero ? 14 : 6, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: prominence == .hero ? 14 : 6, style: .continuous)
          .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
      }
      .shadow(
        color: prominence == .hero ? VhraseTheme.accent.opacity(0.15) : .clear,
        radius: 12,
        y: 5
      )
  }
}
