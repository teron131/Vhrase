// Centralizes Vhrase's named animations and Reduce Motion behavior; motion only answers workflow or pointer changes.

import SwiftUI

enum VhraseMotion {
  static let stateSpring = Animation.spring(response: 0.38, dampingFraction: 0.72)
  static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)
  /// A livelier spring for state changes the user should notice, such as the mic bar changing color.
  static let bounce = Animation.spring(response: 0.34, dampingFraction: 0.58)
  static let press = Animation.spring(response: 0.2, dampingFraction: 0.55)
  static let levelEase = Animation.easeOut(duration: 0.1)
  static let pulse = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
  static let settle = Animation.easeInOut(duration: 0.2)

  static func respectingReduceMotion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : animation
  }
}

/// Reduce Motion keeps the control still.
struct PressableButtonStyle: ButtonStyle {
  var pressedScale: CGFloat = 0.93

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}
