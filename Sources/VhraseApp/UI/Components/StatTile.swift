// Shows one headline number as a chunky tile; a selected tile fills with the accent when the number also drives a chart.

import SwiftUI

struct StatTile: View {
  let value: String
  let title: String
  let detail: String
  var isSelected = false

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(VhraseFont.statValue)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText())
      Text(title)
        .font(VhraseFont.pill)
        .lineLimit(1)
      Text(detail)
        .font(.caption)
        .opacity(0.72)
        .lineLimit(1)
    }
    .foregroundStyle(isSelected ? Color.white : Color.primary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(
      isSelected ? VhraseTheme.accent : VhraseTheme.card,
      in: RoundedRectangle(cornerRadius: VhraseTheme.groupCornerRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: VhraseTheme.groupCornerRadius, style: .continuous)
        .strokeBorder(isSelected ? Color.clear : VhraseTheme.hairline, lineWidth: 1)
    }
  }
}
