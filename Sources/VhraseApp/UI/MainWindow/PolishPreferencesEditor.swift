// Presents provider-independent writing controls with examples that explain each final-output choice.

import SwiftUI

struct PolishPreferencesEditor: View {
  @ObservedObject var appState: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            appState.settings.polishPreferences == .defaults
              ? "Natural · Default" : "Custom writing style"
          )
          .font(.callout.weight(.semibold))
          Text(
            "Default: light rewriting, adaptive formatting, and natural sentence and paragraph breaks."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)
        Button("Reset to default") {
          appState.updateSettings { $0.polishPreferences = .defaults }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.settings.polishPreferences == .defaults)
        .help(
          "Reset all writing preferences, including allowing And or But at the start of sentences. Custom instructions and model settings are kept."
        )
      }

      preferenceGroup("Flow") {
        preferenceRow(
          "Rewrite",
          selection: appState.settingsBinding(\.polishPreferences.rewriteLevel),
          options: PolishRewriteLevel.allCases,
          title: \.title,
          example: \.example
        )
        preferenceRow(
          "Contractions",
          selection: appState.settingsBinding(\.polishPreferences.contractionStyle),
          options: PolishContractionStyle.allCases,
          title: \.title,
          example: \.example
        )
        preferenceRow(
          "Sentences",
          selection: appState.settingsBinding(\.polishPreferences.sentenceStyle),
          options: PolishSentenceStyle.allCases,
          title: \.title,
          example: \.example
        )
        preferenceRow(
          "Paragraphs & lists",
          selection: appState.settingsBinding(\.polishPreferences.structureStyle),
          options: PolishStructureStyle.allCases,
          title: \.title,
          example: \.example
        )
        leadingConjunctionsRow
      }

      preferenceGroup("Formatting") {
        preferenceRow(
          "Numbers",
          selection: appState.settingsBinding(\.polishPreferences.numberStyle),
          options: PolishNumberStyle.allCases,
          title: \.title,
          example: \.example
        )
        preferenceRow(
          "Ordinals",
          selection: appState.settingsBinding(\.polishPreferences.ordinalStyle),
          options: PolishOrdinalStyle.allCases,
          title: \.title,
          example: \.example
        )
        preferenceRow(
          "Money",
          selection: appState.settingsBinding(\.polishPreferences.moneyStyle),
          options: PolishMoneyStyle.allCases,
          title: \.title,
          example: \.example
        )
        preferenceRow(
          "Units",
          selection: appState.settingsBinding(\.polishPreferences.unitStyle),
          options: PolishUnitStyle.allCases,
          title: \.title,
          example: \.example
        )
      }
    }
  }

  private func preferenceGroup<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.title2.weight(.semibold))
        .padding(.bottom, 12)
      content()
    }
  }

  private func preferenceRow<Option: Hashable>(
    _ label: String,
    selection: Binding<Option>,
    options: [Option],
    title: KeyPath<Option, String>,
    example: KeyPath<Option, String>
  ) -> some View {
    HStack(alignment: .center, spacing: 16) {
      Text(label)
        .font(.callout.weight(.medium))
        .frame(width: 120, alignment: .leading)
      examplePreview(selection.wrappedValue[keyPath: example])
      HStack(spacing: 3) {
        ForEach(options, id: \.self) { option in
          Button {
            selection.wrappedValue = option
          } label: {
            Text(option[keyPath: title])
              .font(.caption.weight(selection.wrappedValue == option ? .semibold : .regular))
              .frame(maxWidth: .infinity, minHeight: 22)
              .foregroundStyle(
                selection.wrappedValue == option ? VhraseTheme.accent : Color.secondary
              )
              .background(
                selection.wrappedValue == option ? VhraseTheme.accentSubtle : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
              )
              .contentShape(Rectangle())
          }
          .buttonStyle(PolishChoiceButtonStyle())
          .accessibilityLabel("\(label): \(option[keyPath: title])")
          .accessibilityValue(selection.wrappedValue == option ? "Selected" : "")
        }
      }
      .padding(2)
      .background(VhraseTheme.field, in: RoundedRectangle(cornerRadius: 8))
      .frame(width: 240, alignment: .leading)

    }
    .frame(height: 56)
    .accessibilityElement(children: .contain)
  }

  private var leadingConjunctionsRow: some View {
    preferenceRow(
      "Start with And or But",
      selection: appState.settingsBinding(\.polishPreferences.allowsLeadingConjunctions),
      options: [true, false],
      title: \.conjunctionTitle,
      example: \.conjunctionExample
    )
  }

  /// Keeps source and result visually distinct within the row, beside the trailing controls.
  private func examplePreview(_ example: String) -> some View {
    let parts = example.components(separatedBy: " → ")
    return HStack(spacing: 10) {
      Text(compactExample(parts[0]))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "arrow.right")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
      Text(compactExample(parts.dropFirst().joined(separator: " → ")))
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.callout)
    .lineLimit(2)
    .help(example)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Example: \(example)")
  }

  private func compactExample(_ text: String) -> String {
    text.replacingOccurrences(of: "\n\n", with: " ↵ ")
      .replacingOccurrences(of: "\n", with: " ")
  }
}

extension Bool {
  fileprivate var conjunctionTitle: String { self ? "Allow" : "Avoid" }
  fileprivate var conjunctionExample: String {
    self
      ? "And it's fast. → And it's fast."
      : "It works. And it's fast. → It works, and it's fast."
  }
}

/// Gives the full style segment immediate feedback while the preference is being saved.
private struct PolishChoiceButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        configuration.isPressed ? VhraseTheme.accentSubtle : Color.clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}
