// Draws Vhrase's chunky orange switch while exposing the same on/off semantics as a native toggle to keyboard and VoiceOver users.

import SwiftUI

struct VhraseSwitch: View {
  let title: String
  @Binding var isOn: Bool

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      Capsule()
        .fill(isOn ? VhraseTheme.accent : Color.primary.opacity(0.16))
        .frame(width: 44, height: 26)
        .overlay(alignment: isOn ? .trailing : .leading) {
          Circle()
            .fill(.white)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .padding(3)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Capsule())
    }
    .buttonStyle(PressableButtonStyle(pressedScale: 0.92))
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
      value: isOn
    )
    .accessibilityLabel(title)
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityAddTraits(.isToggle)
  }
}
