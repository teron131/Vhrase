// Centralizes Vhrase's named animations and Reduce Motion behavior.

import SwiftUI

enum VhraseMotion {
  static let stateSpring = Animation.spring(response: 0.38, dampingFraction: 0.72)
  static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)
  static let levelEase = Animation.easeOut(duration: 0.1)
  static let pulse = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
  static let settle = Animation.easeInOut(duration: 0.2)

  static func respectingReduceMotion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : animation
  }
}

private struct HoverLiftModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false

  func body(content: Content) -> some View {
    content
      .offset(y: isHovered && !reduceMotion ? -3 : 0)
      .scaleEffect(isHovered && !reduceMotion ? 1.006 : 1)
      .shadow(
        color: VhraseTheme.accent.opacity(isHovered ? 0.09 : 0),
        radius: 18,
        y: 8
      )
      .onHover { isHovered = $0 }
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.snappy, reduceMotion: reduceMotion),
        value: isHovered)
  }
}

extension View {
  /// Gives pointer-driven surfaces a restrained physical lift without changing layout.
  func hoverLift() -> some View {
    modifier(HoverLiftModifier())
  }
}
