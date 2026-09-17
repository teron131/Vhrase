// Keeps destination typography and form geometry consistent without owning workflow or navigation state.

import AppKit
import SwiftUI

extension View {

  /// Typographic card header; icons stay out of section titles to keep hierarchy editorial.
  func sectionHeader(
    _ title: String,
    description: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(VhraseFont.headline)
      if let description {
        Text(description)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
      }
    }
  }

  /// Establishes a consistent page-level hierarchy before the destination's working controls.
  func pageHeader(
    _ title: String,
    description: String,
    systemImage: String
  ) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(VhraseTheme.accent)
        .frame(width: 40, height: 40)
        .background(
          VhraseTheme.accentSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(VhraseFont.pageTitle)
          .tracking(-0.5)
        Text(description)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
      }
    }
  }

  /// Introduces the currently selected stage before its controls.
  func workflowStageHeader(
    _ title: String,
    description: String,
    systemImage: String
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(VhraseTheme.workflowAccent)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(VhraseFont.headline)
        Text(description)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  func settingsToggle(
    _ title: String,
    detail: String,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(isOn: isOn) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityLabel(title)
    .accessibilityHint(detail)
  }

  func activityMetric(
    _ title: String,
    value: String,
    detail: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(VhraseFont.statValue)
        .foregroundStyle(.primary)
        .contentTransition(.numericText())
      Text(title)
        .font(.callout.weight(.medium))
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  func labeledPicker<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    LabeledContent(title) {
      content()
        .frame(maxWidth: 240)
    }
  }

  func compactField(
    _ title: String,
    text: Binding<String>
  ) -> some View {
    LabeledContent(title) {
      TextField(title, text: text)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 360)
    }
  }

  func editorTile(
    _ title: String,
    systemImage: String,
    text: Binding<String>,
    height: CGFloat,
    instruction: String? = nil,
    placeholder: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.medium))

      if let instruction {
        Text(instruction)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      ZStack(alignment: .topLeading) {
        TextEditor(text: text)
          .font(.body.monospaced())
          .scrollContentBackground(.hidden)
          .accessibilityLabel(title)
          .accessibilityHint(instruction ?? "")

        if text.wrappedValue.isEmpty, let placeholder {
          Text(placeholder)
            .font(.body.monospaced())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .frame(minHeight: height, maxHeight: height)
      .padding(8)
      .insetField()
    }
  }
}
