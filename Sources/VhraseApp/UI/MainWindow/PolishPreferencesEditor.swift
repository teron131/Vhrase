// Presents provider-independent writing controls with examples that explain each final-output choice.

import SwiftUI

struct PolishPreferencesEditor: View {
  @ObservedObject var appState: AppState
  @State private var lastPreset = PolishPreset.minimal

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      presetEditor

      fineTuningOptions
    }
  }

  private var fineTuningOptions: some View {
    VStack(alignment: .leading, spacing: 28) {
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
    settingsGroup("Writing style") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(selectedPreset?.title ?? "Custom")
            .font(VhraseFont.title)
            .foregroundStyle(VhraseTheme.accent)
            .contentTransition(.interpolate)
          Text(
            selectedPreset?.detail
              ?? "Your own combination. Choose a preset or adjust the options below."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        PolishPresetSlider(
          selection: Binding(get: { selectedPreset ?? lastPreset }, set: { applyPreset($0) }),
          isCustom: selectedPreset == nil
        )
        .padding(.top, 4)
      }
      .padding(.vertical, 4)
      .settingsRowStyle()
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
    settingsGroup(title) {
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
        .frame(width: 128, alignment: .leading)
      examplePreview(selection.wrappedValue[keyPath: example])
      PillPicker(
        title: label, selection: selection, options: options,
        label: { $0[keyPath: title] }, fillsWidth: true
      )
      .frame(width: 260)

    }
    .frame(minHeight: 34)
    .settingsRowStyle()
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

  /// Keeps spoken source and written result visually distinct within the row, both set as the user's own words.
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
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(VhraseFont.transcriptBody)
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var lastIndex: Int { PolishPreset.allCases.count - 1 }

  var body: some View {
    GeometryReader { geometry in
      let step = geometry.size.width / CGFloat(PolishPreset.allCases.count)
      let start = step / 2
      let filled = step * CGFloat(selection.rawValue)
      ZStack(alignment: .topLeading) {
        Capsule()
          .fill(VhraseTheme.field)
          .frame(width: step * CGFloat(lastIndex) + 10, height: 10)
          .position(x: geometry.size.width / 2, y: 14)
        Capsule()
          .fill(VhraseTheme.accent)
          .frame(width: filled + 10, height: 10)
          .position(x: start + filled / 2, y: 14)
        ForEach(PolishPreset.allCases) { preset in
          let x = start + step * CGFloat(preset.rawValue)
          let isChosen = !isCustom && selection == preset
          Circle()
            .fill(
              preset.rawValue <= selection.rawValue ? Color.white.opacity(0.85) : Color.secondary
            )
            .frame(width: 4, height: 4)
            .position(x: x, y: 14)
          Button {
            selection = preset
          } label: {
            Text(preset.title)
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
              selection = PolishPreset.allCases[index]
            })
      }
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
        value: selection
      )
    }
    .frame(height: 62)
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
