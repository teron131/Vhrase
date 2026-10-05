// Presents the transcription sequence as numbered stage pills whose selected stage owns the editor below them.

import SwiftUI

/// Stable stage identities keep editor selection intact while live summaries change.
enum PipelineStage: String, Hashable {
  case trigger
  case listen
  case transcribe
}

/// Describes one stage and the live state summarized in the workflow strip.
struct PipelineFlowNode: Equatable {
  let id: PipelineStage
  let title: String
  let detail: String
  var badge: String?
}

/// Acts as navigation for one stage-owned settings editor; stage numbers encode the order audio travels.
struct PipelineFlowView: View {
  let nodes: [PipelineFlowNode]
  @Binding var selection: PipelineStage

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hoveredStage: PipelineStage?

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
        nodeButton(node, number: index + 1)
        if index < nodes.count - 1 {
          Line()
            .stroke(
              VhraseTheme.hairline,
              style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6])
            )
            .frame(minWidth: 16, maxWidth: .infinity)
            .frame(height: 2)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
        }
      }
    }
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
      value: selection
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Workflow stages")
  }

  private func nodeButton(_ node: PipelineFlowNode, number: Int) -> some View {
    let isSelected = selection == node.id
    let isHovered = hoveredStage == node.id
    let summary = [node.detail, node.badge].compactMap { $0 }.joined(separator: " · ")

    return Button {
      selection = node.id
    } label: {
      HStack(spacing: 10) {
        Text("\(number)")
          .font(.system(.callout, design: .rounded, weight: .heavy).monospacedDigit())
          .foregroundStyle(isSelected ? VhraseTheme.accent : Color.secondary)
          .frame(width: 28, height: 28)
          .background(Circle().fill(isSelected ? Color.white : VhraseTheme.field))

        VStack(alignment: .leading, spacing: 1) {
          Text(node.title)
            .font(.system(.body, design: .rounded, weight: .bold))
          Text(summary)
            .font(.caption)
            .opacity(0.8)
            .lineLimit(1)
        }
      }
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .fixedSize()
      .padding(.leading, 6)
      .padding(.trailing, 18)
      .padding(.vertical, 6)
      .background {
        Capsule()
          .fill(
            isSelected ? VhraseTheme.accent : (isHovered ? VhraseTheme.field : VhraseTheme.card))
      }
      .contentShape(Capsule())
    }
    .buttonStyle(PressableButtonStyle(pressedScale: 0.95))
    .onHover { isHovering in
      hoveredStage = isHovering ? node.id : nil
    }
    .accessibilityLabel("Stage \(number), \(node.title)")
    .accessibilityValue(isSelected ? "\(summary), Selected" : summary)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityHint("Shows settings for this stage")
  }
}

/// A horizontal center line for dashed connectors between stage pills.
private struct Line: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    return path
  }
}
