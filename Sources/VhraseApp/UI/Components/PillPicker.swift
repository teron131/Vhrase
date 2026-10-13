// Chooses one option from a short list as chunky text or icon pills; the chosen pill fills with the accent so the current choice reads at a glance.

import SwiftUI

struct PillPicker<Option: Hashable>: View {
  let title: String
  @Binding var selection: Option
  let options: [Option]
  let label: (Option) -> String
  /// Equal-width pills keep stacked rows of choices aligned; otherwise each pill hugs its label.
  var fillsWidth = false
  /// Draws an SF Symbol in each pill instead of its label; the label then names the choice for VoiceOver and the tooltip.
  var systemImage: ((Option) -> String)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.self) { option in
        let isSelected = selection == option
        Button {
          selection = option
        } label: {
          Group {
            if let systemImage {
              Image(systemName: systemImage(option))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
            } else {
              Text(label(option))
                .font(VhraseFont.pill)
                .lineLimit(1)
            }
          }
          .padding(.horizontal, fillsWidth ? 6 : 12)
          .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 26)
          .foregroundStyle(isSelected ? Color.white : Color.secondary)
          .background {
            if isSelected {
              Capsule()
                .fill(VhraseTheme.accent)
                .matchedGeometryEffect(id: "selection", in: selectionNamespace)
            }
          }
          .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.95))
        .help(systemImage == nil ? "" : label(option))
        .accessibilityLabel("\(title): \(label(option))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(3)
    .background(Capsule().fill(VhraseTheme.field))
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
      value: selection
    )
  }
}
