// Presents provider-independent writing controls with examples that explain each final-output choice.

import SwiftUI

struct PolishPreferencesEditor: View {
  @ObservedObject var appState: AppState
  @State private var lastPreset = PolishPreset.minimal

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      presetEditor

      fineTuningOptions
    }
  }

  private var fineTuningOptions: some View {
    VStack(alignment: .leading, spacing: 24) {
      preferenceGroup("Flow") {
        preferenceRow(
          "Rewrite",
          selection: appState.settingsBinding(\.polishPreferences.rewriteLevel),
          options: PolishRewriteLevel.allCases,
          title: \.title,
          example: \.example
        )
        fillerWordsRow
        spokenCorrectionsRow
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

  private var preferences: PolishPreferences {
    appState.settings.polishPreferences
  }

  private var selectedPreset: PolishPreset? {
    PolishPreset.matching(preferences)
  }

  private var presetEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Writing style")
          .font(.callout.weight(.semibold))
        Spacer()
        Text(selectedPreset?.title ?? "Custom")
          .font(.callout.weight(.semibold))
          .foregroundStyle(VhraseTheme.accent)
      }
      PolishPresetSlider(
        selection: Binding(get: { selectedPreset ?? lastPreset }, set: { applyPreset($0) }),
        isCustom: selectedPreset == nil
      )

      Text(
        selectedPreset?.detail
          ?? "Your own combination. Choose a preset or adjust the options below."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

    }
  }

  private func applyPreset(_ preset: PolishPreset) {
    lastPreset = preset
    appState.updateSettings { $0.polishPreferences = preset.preferences }
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

  private var fillerWordsRow: some View {
    preferenceRow(
      "Filler words",
      selection: appState.settingsBinding(\.polishPreferences.removesFillerWords),
      options: [false, true],
      title: \.fillerWordTitle,
      example: \.fillerWordExample
    )
  }

  private var spokenCorrectionsRow: some View {
    preferenceRow(
      "Spoken corrections",
      selection: appState.settingsBinding(\.polishPreferences.resolvesSpokenCorrections),
      options: [false, true],
      title: \.spokenCorrectionTitle,
      example: \.spokenCorrectionExample
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

/// Places track, ticks, thumb, labels, and drag snapping on the same five coordinates.
private struct PolishPresetSlider: View {
  @Binding var selection: PolishPreset
  let isCustom: Bool
  private var lastIndex: Int { PolishPreset.allCases.count - 1 }

  var body: some View {
    GeometryReader { geometry in
      let step = geometry.size.width / CGFloat(PolishPreset.allCases.count)
      let start = step / 2
      let filled = step * CGFloat(selection.rawValue)
      ZStack(alignment: .topLeading) {
        Capsule()
          .fill(VhraseTheme.hairline)
          .frame(width: step * CGFloat(lastIndex), height: 4)
          .position(x: geometry.size.width / 2, y: 12)
        Capsule()
          .fill(VhraseTheme.accent)
          .frame(width: filled, height: 4)
          .position(x: start + filled / 2, y: 12)
        ForEach(PolishPreset.allCases) { preset in
          let x = start + step * CGFloat(preset.rawValue)
          Capsule()
            .fill(preset.rawValue <= selection.rawValue ? VhraseTheme.accent : Color.secondary)
            .frame(width: 2, height: 10)
            .position(x: x, y: 12)
          Button(preset.title) { selection = preset }
            .buttonStyle(.plain)
            .font(.caption.weight(!isCustom && selection == preset ? .semibold : .regular))
            .foregroundStyle(
              !isCustom && selection == preset ? VhraseTheme.accent : Color.secondary
            )
            .frame(width: step)
            .position(x: x, y: 38)
        }
        Circle()
          .fill(Color(white: 0.85))
          .frame(width: 18, height: 18)
          .position(x: start + filled, y: 12)
        Rectangle()
          .fill(Color.clear)
          .frame(height: 26)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
              let index = min(lastIndex, max(0, Int(((value.location.x - start) / step).rounded())))
              selection = PolishPreset.allCases[index]
            })
      }
    }
    .frame(height: 50)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Writing style preset")
    .accessibilityValue(isCustom ? "Custom" : selection.title)
    .accessibilityAdjustableAction { direction in
      let delta = direction == .increment ? 1 : -1
      selection = PolishPreset.allCases[min(lastIndex, max(0, selection.rawValue + delta))]
    }
  }
}

extension Bool {
  fileprivate var conjunctionTitle: String { self ? "Allow" : "Avoid" }
  fileprivate var conjunctionExample: String {
    self
      ? "And it's fast. → And it's fast."
      : "It works. And it's fast. → It works, and it's fast."
  }

  fileprivate var fillerWordTitle: String { self ? "Remove" : "Keep" }
  fileprivate var fillerWordExample: String {
    self ? "Um, we should go. → We should go." : "Um, we should go. → Um, we should go."
  }

  fileprivate var spokenCorrectionTitle: String { self ? "Resolve" : "Keep" }
  fileprivate var spokenCorrectionExample: String {
    self
      ? "the first, no, second → the second"
      : "the first, no, second → the first, no, second"
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
