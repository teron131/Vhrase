// Presents a compact vertical workflow whose selected stage owns the adjacent settings editor.

import SwiftUI

/// Stable stage identities keep editor selection intact while live summaries change.
enum PipelineStage: String, Hashable {
  case trigger
  case listen
  case transcribe
}

/// Describes one stage and the live state summarized in the workflow rail.
struct PipelineFlowNode: Equatable {
  let id: PipelineStage
  let systemImage: String
  let title: String
  let detail: String
  var badge: String?
}

/// Acts as navigation for one stage-owned settings editor.
struct PipelineFlowView: View {
  let nodes: [PipelineFlowNode]
  @Binding var selection: PipelineStage

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hoveredStage: PipelineStage?
  @State private var flowProgress: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
        nodeButton(node)
        if index < nodes.count - 1 {
          connector
        }
      }
    }
    .padding(.vertical, 4)
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.snappy, reduceMotion: reduceMotion),
      value: selection
    )
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.snappy, reduceMotion: reduceMotion),
      value: hoveredStage
    )
    .onAppear {
      guard !reduceMotion else {
        return
      }
      withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
        flowProgress = 1
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Workflow stages")
  }

  private func nodeButton(_ node: PipelineFlowNode) -> some View {
    let isSelected = selection == node.id
    let isHovered = hoveredStage == node.id
    let background =
      isSelected
      ? VhraseTheme.workflowAccent.opacity(0.085)
      : (isHovered ? Color.primary.opacity(0.025) : .clear)

    return Button {
      selection = node.id
    } label: {
      HStack(spacing: 12) {
        Image(systemName: node.systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(VhraseTheme.workflowAccent)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 3) {
          Text(node.title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)

          Text(node.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          if let badge = node.badge {
            Text(badge)
              .font(.caption2.weight(.medium))
              .foregroundStyle(VhraseTheme.workflowAccent)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 4)

        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(
            isSelected
              ? VhraseTheme.workflowAccent
              : VhraseTheme.inkSecondary.opacity(0.5)
          )
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(background)
      .overlay(alignment: .leading) {
        if isSelected {
          Capsule()
            .fill(VhraseTheme.workflowAccent)
            .frame(width: 3)
            .padding(.vertical, 10)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering in
      hoveredStage = isHovering ? node.id : nil
    }
    .accessibilityLabel(node.title)
    .accessibilityValue(isSelected ? "\(node.detail), Selected" : node.detail)
    .accessibilityHint("Shows settings for this stage")
  }

  private var connector: some View {
    HStack(spacing: 0) {
      ZStack(alignment: .top) {
        Capsule()
          .fill(VhraseTheme.hairline)
          .frame(width: 2)

        Capsule()
          .fill(VhraseTheme.workflowAccent.opacity(0.45))
          .frame(width: 2)

        if !reduceMotion {
          Circle()
            .fill(VhraseTheme.workflowAccent)
            .frame(width: 5, height: 5)
            .shadow(color: VhraseTheme.workflowAccent.opacity(0.4), radius: 4)
            .offset(y: 19 * flowProgress)
        }
      }
      .frame(width: 32, height: 24)
      .padding(.leading, 14)

      Spacer()
    }
    .accessibilityHidden(true)
  }
}
