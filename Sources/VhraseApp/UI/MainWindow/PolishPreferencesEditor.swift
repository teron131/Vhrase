// Groups Polishing's style settings by the operation that uses them, heads each group with thumbnails of the gestures that use it, and previews Restyle on recent dictations.

import SwiftUI

struct PolishPreferencesEditor: View {
  @ObservedObject var appState: AppState
  @State private var lastPreset = PolishPreset.minimal

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      refineEditor
      restyleEditor
      sharedEditor
    }
  }

  private var hasHistory: Bool { !appState.history.isEmpty }

  private var refineEditor: some View {
    settingsGroup("Refine") {
      presetEditor
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

      if hasHistory {
        PolishTestView(appState: appState, operation: .refine)
          .settingsRowStyle()
      }
    } accessory: {
      dictationRoute(isActive: appState.settings.afterTranscription == .refine)
    }
  }

  private var restyleEditor: some View {
    settingsGroup("Restyle") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(appState.settings.polishStyle.title)
            .font(VhraseFont.title)
            .foregroundStyle(VhraseTheme.accent)
          Text(appState.settings.restyleChoice.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        PillPicker(
          title: "Restyle style", selection: appState.settingsBinding(\.restyleChoice),
          options: RestyleChoice.allCases, label: { $0.title }, fillsWidth: true
        )
        // Recent dictations replace the built-in example as the preview once History has any.
        if !hasHistory, let example = appState.settings.restyleChoice.example {
          examplePreview(example)
        }
      }
      .settingsRowStyle()

      if appState.settings.restyleChoice == .custom {
        settingsRow("Name") {
          TextField("Custom", text: appState.settingsBinding(\.customRestyleName))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .accessibilityLabel("Custom style name")
            .frame(width: 320)
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Instruction")
          editorTile(
            "Custom Restyle instruction",
            text: appState.settingsBinding(\.customRestyleInstruction), height: 96,
            instruction:
              "Double-tap uses this instruction. Dictation uses it too when After transcription is set to Restyle.",
            placeholder: "Rewrite as a concise message. Keep every detail and request."
          )
        }
        .settingsRowStyle()
      }

      if hasHistory {
        PolishTestView(appState: appState, operation: .restyle(appState.settings.polishStyle))
          .settingsRowStyle()
      }
    } accessory: {
      HStack(spacing: 6) {
        doubleTapRoute
        dictationRoute(isActive: appState.settings.afterTranscription == .restyle)
      }
    }
  }

  private var doubleTapRoute: some View {
    RouteThumbnail(
      title: "Double-tap", timeline: .doubleTap, isActive: true,
      help: "Double-tap restyles the selected text, or the whole field.")
  }

  private func dictationRoute(isActive: Bool) -> some View {
    RouteThumbnail(
      title: "Dictation", timeline: Self.polishedDictation, isActive: isActive,
      help: "After transcription is set to \(appState.settings.afterTranscription.title).")
  }

  private static let polishedDictation = GestureTimeline(
    presses: [0.06...0.15, 0.56...0.65], recording: 0.06...0.60, outcome: "wand.and.stars",
    outcomeAt: 0.84)

  private var sharedEditor: some View {
    settingsGroup("All") {
      fillerWordsRow
      spokenCorrectionsRow
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
      VStack(alignment: .leading, spacing: 8) {
        Text("Additional instructions")
        editorTile(
          "Additional instructions", text: appState.settingsBinding(\.adjustmentPrompt), height: 96,
          instruction:
            "Optional instructions for the LLM. These take priority over Refine preferences and shared formatting, but not the chosen Restyle style.",
          placeholder: "Keep Jira issue keys unchanged. Use British spelling."
        )
      }
      .settingsRowStyle()
    } accessory: {
      HStack(spacing: 6) {
        doubleTapRoute
        dictationRoute(isActive: appState.settings.afterTranscription.usesLLM)
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
      StepSlider(
        title: "Writing style preset",
        options: PolishPreset.allCases,
        selection: Binding(get: { selectedPreset ?? lastPreset }, set: { applyPreset($0) }),
        isCustom: selectedPreset == nil,
        label: \.title
      )
      .padding(.top, 4)
    }
    .padding(.vertical, 4)
    .settingsRowStyle()
  }

  private func applyPreset(_ preset: PolishPreset) {
    lastPreset = preset
    appState.updateSettings { $0.polishPreferences = preset.preferences }
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

/// Dims to the Shortcut page's switched-off opacity when the route doesn't use the group, so "off" reads the same on both pages.
private struct RouteThumbnail: View {
  let title: String
  let timeline: GestureTimeline
  let isActive: Bool
  let help: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      timeline
        .frame(width: 60)
      Text(title)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .surface(cornerRadius: 8)
    .opacity(isActive ? 1 : 0.4)
    .help(help)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) \(isActive ? "uses" : "doesn't use") these settings")
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
