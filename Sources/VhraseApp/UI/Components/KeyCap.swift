// Renders keyboard shortcuts as physical key caps wherever Vhrase names its global shortcut.

import SwiftUI

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
      .padding(.horizontal, prominence == .hero ? 18 : 7)
      .padding(.vertical, prominence == .hero ? 10 : 3)
      .background(
        VhraseTheme.field,
        in: RoundedRectangle(cornerRadius: prominence == .hero ? 10 : 5, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: prominence == .hero ? 10 : 5, style: .continuous)
          .strokeBorder(VhraseTheme.hairline, lineWidth: 1)
      }
  }
}
