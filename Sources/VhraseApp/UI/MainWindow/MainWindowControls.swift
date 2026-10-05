// Keeps destination headers and settings geometry consistent without owning workflow or navigation state.

import AppKit
import SwiftUI

/// Bounds every destination to one readable column so labels, controls, and transcripts share an edge.
private let mainWindowContentWidth: CGFloat = 860

extension View {

  /// Typographic section header; icons stay out of section titles to keep hierarchy editorial.
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

  /// Opens each destination with its name and one sentence of purpose.
  func pageHeader(_ title: String, description: String) -> some View {
    pageHeader(title, description: description) { EmptyView() }
  }

  /// Opens a destination whose page-wide actions share the title row instead of floating inside a section.
  func pageHeader<Accessory: View>(
    _ title: String,
    description: String,
    @ViewBuilder accessory: () -> Accessory
  ) -> some View {
    HStack(alignment: .bottom, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(VhraseFont.pageTitle)
          .tracking(-0.4)
          .accessibilityAddTraits(.isHeader)
        Text(description)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 16)
      accessory()
    }
  }

  /// Places one page's sections in the shared scrolling column on the window canvas.
  func mainWindowPage<Content: View>(
    spacing: CGFloat = 28,
    @ViewBuilder content: () -> Content
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: spacing) {
        content()
      }
      .frame(maxWidth: mainWindowContentWidth, alignment: .topLeading)
      .padding(.horizontal, 36)
      .padding(.top, 28)
      .padding(.bottom, 40)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  /// Groups related settings on one card; each row draws its own separator and the card hides the first one.
  func settingsGroup<Content: View>(
    _ title: String? = nil,
    footer: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    settingsGroup(title, footer: footer, content: content) { EmptyView() }
  }

  /// Groups related settings whose group-wide action, such as a refresh, sits on the heading row.
  func settingsGroup<Content: View, Accessory: View>(
    _ title: String?,
    footer: String? = nil,
    @ViewBuilder content: () -> Content,
    @ViewBuilder accessory: () -> Accessory
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        HStack(alignment: .lastTextBaseline) {
          Text(title)
            .font(VhraseFont.headline)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          accessory()
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        content()
      }
      .mask {
        RoundedRectangle(cornerRadius: VhraseTheme.groupCornerRadius, style: .continuous)
          .padding(.top, 1)
      }
      .surface()
      if let footer {
        Text(footer)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// Gives custom content the padding and leading separator of a settings row.
  func settingsRowStyle() -> some View {
    padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(VhraseTheme.hairline)
          .frame(height: 1)
          .padding(.leading, 14)
      }
  }

  /// Lays out one setting with its explanation leading and its control on the group's shared trailing edge.
  func settingsRow<Control: View>(
    _ title: String,
    detail: String? = nil,
    @ViewBuilder control: () -> Control
  ) -> some View {
    HStack(alignment: .center, spacing: 20) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      control()
        .fixedSize(horizontal: true, vertical: false)
    }
    .settingsRowStyle()
  }

  func settingsToggle(
    _ title: String,
    detail: String? = nil,
    isOn: Binding<Bool>
  ) -> some View {
    settingsRow(title, detail: detail) {
      VhraseSwitch(title: title, isOn: isOn)
        .accessibilityHint(detail ?? "")
    }
  }

  /// Pairs a slider with its current value so every tuning row reads the same way.
  func settingsSlider(
    _ title: String,
    detail: String? = nil,
    value: Binding<Double>,
    in range: ClosedRange<Double>,
    step: Double,
    valueLabel: String
  ) -> some View {
    settingsRow(title, detail: detail) {
      HStack(spacing: 10) {
        Slider(value: value, in: range, step: step)
          .labelsHidden()
          .accessibilityLabel(title)
          .accessibilityValue(valueLabel)
        Text(valueLabel)
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 56, alignment: .trailing)
      }
      .frame(width: 280)
    }
  }

  /// Pairs a stepper with its current value and unit, keeping the number in the shared trailing column.
  func settingsStepper<Value: Strideable & Comparable>(
    _ title: String,
    detail: String? = nil,
    value: Binding<Value>,
    in range: ClosedRange<Value>,
    step: Value.Stride,
    valueLabel: String
  ) -> some View {
    settingsRow(title, detail: detail) {
      HStack(spacing: 8) {
        Text(valueLabel)
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
        Stepper(title, value: value, in: range, step: step)
          .labelsHidden()
          .accessibilityValue(valueLabel)
      }
    }
  }

  /// Edits multi-line text inside a settings group, whose heading names it; the title labels it for accessibility.
  func editorTile(
    _ title: String,
    text: Binding<String>,
    height: CGFloat,
    instruction: String? = nil,
    placeholder: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let instruction {
        Text(instruction)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
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
