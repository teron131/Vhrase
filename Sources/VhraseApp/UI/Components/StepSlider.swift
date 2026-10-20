// Steps one choice along a short ordered scale, such as writing presets or screenshot sizes, with every stop labeled under the track.

import SwiftUI

struct StepSlider<Option: Hashable>: View {
  let title: String
  let options: [Option]
  @Binding var selection: Option
  /// Keeps the thumb on the previous choice without highlighting its label, for settings edited off the scale.
  var isCustom = false
  let label: (Option) -> String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var lastIndex: Int { options.count - 1 }
  private var selectedIndex: Int { options.firstIndex(of: selection) ?? 0 }

  var body: some View {
    GeometryReader { geometry in
      let step = geometry.size.width / CGFloat(options.count)
      let start = step / 2
      let filled = step * CGFloat(selectedIndex)
      ZStack(alignment: .topLeading) {
        Capsule()
          .fill(VhraseTheme.field)
          .frame(width: step * CGFloat(lastIndex) + 10, height: 10)
          .position(x: geometry.size.width / 2, y: 14)
        Capsule()
          .fill(VhraseTheme.accent)
          .frame(width: filled + 10, height: 10)
          .position(x: start + filled / 2, y: 14)
        ForEach(options.indices, id: \.self) { index in
          let option = options[index]
          let x = start + step * CGFloat(index)
          let isChosen = !isCustom && selection == option
          Circle()
            .fill(index <= selectedIndex ? Color.white.opacity(0.85) : Color.secondary)
            .frame(width: 4, height: 4)
            .position(x: x, y: 14)
          Button {
            selection = option
          } label: {
            Text(label(option))
              .font(VhraseFont.pill)
              .foregroundStyle(isChosen ? Color.white : Color.secondary)
              .padding(.horizontal, 10)
              .padding(.vertical, 3)
              .background {
                if isChosen {
                  Capsule().fill(VhraseTheme.accent)
                }
              }
              .contentShape(Capsule())
          }
          .buttonStyle(PressableButtonStyle(pressedScale: 0.94))
          .frame(width: step)
          .position(x: x, y: 46)
        }
        Circle()
          .fill(.white)
          .overlay { Circle().strokeBorder(VhraseTheme.accent, lineWidth: 3) }
          .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
          .frame(width: 26, height: 26)
          .position(x: start + filled, y: 14)
        Rectangle()
          .fill(Color.clear)
          .frame(height: 30)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
              let index = min(lastIndex, max(0, Int(((value.location.x - start) / step).rounded())))
              selection = options[index]
            })
      }
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
        value: selection
      )
    }
    .frame(height: 62)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(isCustom ? "Custom" : label(selection))
    .accessibilityAdjustableAction { direction in
      let delta = direction == .increment ? 1 : -1
      selection = options[min(lastIndex, max(0, selectedIndex + delta))]
    }
  }
}
